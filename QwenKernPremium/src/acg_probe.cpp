#include "acg_probe.h"

#include <tlhelp32.h>
#include <intrin.h>

#include <cstdio>
#include <cstring>

// ============================================================================
// Native (ntdll) entry points, resolved at runtime.
//
// Declared by hand on purpose: winternl.h's NTSTATUS/NtProtectVirtualMemory
// declarations collide with ntdll's own ABI in annoying ways, and resolving
// dynamically keeps ntdll out of our static import table (GATE 0).
//
// NOTE ON SCOPE: these helpers are deliberately NOT in an anonymous namespace.
// MSVC raises C2888 ("symbol cannot be defined within namespace
// 'anonymous-namespace'") for every out-of-class definition of AcgProbe::* if
// the file is wrapped in `namespace { ... }`.  Members therefore live at global
// scope, and the helpers are prefixed where a name could plausibly collide
// (Probe*, Acg*) while const objects keep internal linkage by default.
// ============================================================================
typedef LONG (NTAPI *NtAllocateVirtualMemoryFn)(HANDLE, PVOID*, ULONG_PTR, PSIZE_T,
                                                ULONG, ULONG);
typedef LONG (NTAPI *NtProtectVirtualMemoryFn)(HANDLE, PVOID*, PSIZE_T, ULONG, PULONG);
typedef LONG (NTAPI *NtCreateSectionFn)(PHANDLE, ACCESS_MASK, PVOID, PLARGE_INTEGER,
                                       ULONG, ULONG, HANDLE);
typedef LONG (NTAPI *NtMapViewOfSectionFn)(HANDLE, HANDLE, PVOID*, ULONG_PTR, SIZE_T,
                                          PLARGE_INTEGER, PSIZE_T, ULONG, ULONG, ULONG);
typedef LONG (NTAPI *NtUnmapViewOfSectionFn)(HANDLE, PVOID);
typedef LONG (NTAPI *NtCreateThreadExFn)(PHANDLE, ACCESS_MASK, PVOID, HANDLE, PVOID,
                                         PVOID, ULONG, SIZE_T, SIZE_T, SIZE_T, PVOID);
typedef LONG (NTAPI *RtlGetVersionFn)(RTL_OSVERSIONINFOW*);
typedef LONG (WINAPI *RegGetValueAFn)(HKEY, LPCSTR, LPCSTR, DWORD, LPDWORD, PVOID, LPDWORD);
typedef LONG (NTAPI *NtQueryInformationProcessFn)(HANDLE, ULONG, PVOID, ULONG, PULONG);
typedef BOOL (WINAPI *EnumProcessModulesExFn)(HANDLE, HMODULE*, DWORD, LPDWORD, DWORD);

const ULONG kPageExecuteReadWrite = PAGE_EXECUTE_READWRITE;
const ULONG kPageExecuteRead      = PAGE_EXECUTE_READ;
const ULONG kPageReadWrite        = PAGE_READWRITE;
const ULONG kPageReadOnly         = PAGE_READONLY;

// SECTION_INHERIT::ViewUnmap - winternl.h is not included, so pin the value
// (it is the documented, ABI-stable enum member value 2).
const ULONG kViewUnmap = 2;

const SIZE_T kProbeSize = 0x1000;   // one page is enough for every primitive

template <typename TFunc>
TFunc ResolveFrom(const char* moduleName, const char* exportName) {
    HMODULE module = GetModuleHandleA(moduleName);
    if (!module) module = LoadLibraryA(moduleName);
    if (!module) return nullptr;
    return reinterpret_cast<TFunc>(GetProcAddress(module, exportName));
}

NtAllocateVirtualMemoryFn  NtAllocateVirtualMemory()  { static auto f = ResolveFrom<NtAllocateVirtualMemoryFn>("ntdll.dll", "NtAllocateVirtualMemory");  return f; }
NtProtectVirtualMemoryFn   NtProtectVirtualMemory()   { static auto f = ResolveFrom<NtProtectVirtualMemoryFn>("ntdll.dll", "NtProtectVirtualMemory");    return f; }
NtCreateSectionFn          NtCreateSection()          { static auto f = ResolveFrom<NtCreateSectionFn>("ntdll.dll", "NtCreateSection");                  return f; }
NtMapViewOfSectionFn       NtMapViewOfSection()       { static auto f = ResolveFrom<NtMapViewOfSectionFn>("ntdll.dll", "NtMapViewOfSection");            return f; }
NtUnmapViewOfSectionFn     NtUnmapViewOfSection()     { static auto f = ResolveFrom<NtUnmapViewOfSectionFn>("ntdll.dll", "NtUnmapViewOfSection");        return f; }
NtCreateThreadExFn         NtCreateThreadEx()         { static auto f = ResolveFrom<NtCreateThreadExFn>("ntdll.dll", "NtCreateThreadEx");                return f; }
NtQueryInformationProcessFn NtQueryInformationProcess() { static auto f = ResolveFrom<NtQueryInformationProcessFn>("ntdll.dll", "NtQueryInformationProcess"); return f; }

std::string Hex(ULONGLONG value) {
    char buffer[32] = { 0 };
    sprintf_s(buffer, sizeof(buffer), "0x%llX", static_cast<unsigned long long>(value));
    return std::string(buffer);
}

std::string StatusText(LONG status) {
    if (status == 0) return std::string("STATUS_SUCCESS");
    char buffer[32] = { 0 };
    sprintf_s(buffer, sizeof(buffer), "0x%08lX", static_cast<unsigned long>(status));
    return std::string(buffer);
}

ProbeResult MakeResult(const char* id, const char* title, bool passed, LONG status,
                       DWORD win32Error, ULONGLONG address, std::size_t size,
                       const std::string& detail) {
    ProbeResult result{};
    result.id         = id ? id : "";
    result.title      = title ? title : "";
    result.passed     = passed;
    result.status     = status;
    result.win32Error = win32Error;
    result.address    = address;
    result.size       = size;
    result.detail     = detail;
    return result;
}

// A 17-byte x64 stub: `mov ecx,0; mov rax,<abs64>; call rax` calling ExitThread.
// Writing it into a freshly obtained region and running it is the only honest
// proof that the region is executable (and that a remote thread can run there).
void BuildExitThreadStub(unsigned char* buffer, ULONGLONG exitThreadAddress) {
    std::size_t offset = 0;
    buffer[offset++] = 0xB9;                                   // mov ecx, imm32
    buffer[offset++] = 0x00; buffer[offset++] = 0x00;
    buffer[offset++] = 0x00; buffer[offset++] = 0x00;
    buffer[offset++] = 0x48; buffer[offset++] = 0xB8;          // mov rax, imm64
    for (int i = 0; i < 8; ++i) buffer[offset++] = static_cast<unsigned char>((exitThreadAddress >> (8 * i)) & 0xFF);
    buffer[offset++] = 0xFF; buffer[offset++] = 0xD0;          // call rax
}
const std::size_t kStubSize = 17;

ULONGLONG ExitThreadAddress() {
    return reinterpret_cast<ULONGLONG>(
        GetProcAddress(GetModuleHandleA("kernel32.dll"), "ExitThread"));
}

// Execute the ExitThread stub that already sits at `address`.  The stub never
// returns (ExitThread ends the thread), so this is safe to call in place.
bool RunInPlaceStub(void* address) {
    typedef void (WINAPI* StubFn)();
    reinterpret_cast<StubFn>(address)();
    return true;
}

// A false "absent" is the easiest lie to tell with this probe: when the target's
// module list cannot be read at all (the live Javelin/Apex blackout) the truth is
// UNKNOWN, and a payload that loaded perfectly would be blamed for it.  A zero
// module count means we are blind, so report "unknown" instead of "absent".
std::string ModulePresenceText(bool loaded, int moduleCount) {
    if (loaded) return "loaded";
    return (moduleCount == 0) ? "unknown" : "absent";
}

ULONG RunReturnStub(void* address) {
    typedef ULONG (WINAPI *StubFn)();
    return reinterpret_cast<StubFn>(address)();
}

std::string OsVersionText() {
    RtlGetVersionFn rtlGetVersion = ResolveFrom<RtlGetVersionFn>("ntdll.dll", "RtlGetVersion");
    if (!rtlGetVersion) return "unknown";

    RTL_OSVERSIONINFOW info{};
    info.dwOSVersionInfoSize = sizeof(info);
    if (rtlGetVersion(&info) != 0) return "unknown";

    char buffer[96] = { 0 };
    sprintf_s(buffer, sizeof(buffer), "%lu.%lu build %lu",
              static_cast<unsigned long>(info.dwMajorVersion),
              static_cast<unsigned long>(info.dwMinorVersion),
              static_cast<unsigned long>(info.dwBuildNumber));
    return std::string(buffer);
}

// HVCI / Memory Integrity.  Read straight from the registry: the ACG behaviour
// the KB documents differs between HVCI-on and HVCI-off machines, so a probe
// result without this field is not comparable to another machine's result.
std::string HvciText(bool& advapi32WasLoaded) {
    HMODULE advapi32 = GetModuleHandleA("advapi32.dll");
    advapi32WasLoaded = (advapi32 != nullptr);
    if (!advapi32) advapi32 = LoadLibraryA("advapi32.dll");
    if (!advapi32) return "unknown";

    RegGetValueAFn regGetValue = reinterpret_cast<RegGetValueAFn>(
        GetProcAddress(advapi32, "RegGetValueA"));
    if (!regGetValue) return "unknown";

    DWORD value = 0;
    DWORD size  = sizeof(value);
    const LONG status = regGetValue(
        HKEY_LOCAL_MACHINE,
        "SYSTEM\\CurrentControlSet\\Control\\DeviceGuard\\Scenarios\\HypervisorEnforcedCodeIntegrity",
        "Enabled", RRF_RT_REG_DWORD, nullptr, &value, &size);
    if (status != 0) return "unknown (key absent)";
    return value ? "enabled" : "disabled";
}

std::string CpuText() {
    int registers[4] = { 0, 0, 0, 0 };
    __cpuid(registers, 0);
    char vendor[13] = { 0 };
    std::memcpy(vendor, &registers[1], 4);
    std::memcpy(vendor + 4, &registers[3], 4);
    std::memcpy(vendor + 8, &registers[2], 4);

    __cpuid(registers, 1);
    const bool hypervisor = (registers[2] & (1 << 31)) != 0;

    return std::string(vendor) + (hypervisor ? " (hypervisor bit set)"
                                             : " (no hypervisor bit)");
}

void CollectModules(DWORD pid, ProbeEnvironment& env) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    if (snapshot == INVALID_HANDLE_VALUE) return;

    MODULEENTRY32 entry{};
    entry.dwSize = sizeof(entry);

    if (Module32First(snapshot, &entry)) {
        do {
            ++env.moduleCount;
            if (_stricmp(entry.szModule, "d3d11.dll") == 0) env.d3d11Loaded = true;
            if (_stricmp(entry.szModule, "dxgi.dll")  == 0) env.dxgiLoaded  = true;
            if (_stricmp(entry.szModule, "d3d12.dll") == 0) env.d3d12Loaded = true;
            if (_stricmp(entry.szModule, "d3d9.dll")  == 0) env.d3d9Loaded  = true;
            if (_stricmp(entry.szModule, "d3dcompiler_47.dll") == 0) env.d3dCompilerLoaded = true;
        } while (Module32Next(snapshot, &entry));
    }

    CloseHandle(snapshot);
}

std::string ProcessImageName(DWORD pid) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return "unknown";

    PROCESSENTRY32 entry{};
    entry.dwSize = sizeof(entry);

    std::string name = "unknown";
    if (Process32First(snapshot, &entry)) {
        do {
            if (entry.th32ProcessID == pid) { name = entry.szExeFile; break; }
        } while (Process32Next(snapshot, &entry));
    }

    CloseHandle(snapshot);
    return name;
}

ULONGLONG MainModuleBase(DWORD pid) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;

    MODULEENTRY32 entry{};
    entry.dwSize = sizeof(entry);

    ULONGLONG base = 0;
    if (Module32First(snapshot, &entry)) {
        base = reinterpret_cast<ULONGLONG>(entry.modBaseAddr);
    }

    CloseHandle(snapshot);
    return base;
}

// ============================================================================
// Environment
// ============================================================================
ProbeEnvironment AcgProbe::DescribeProcess(DWORD pid) {
    ProbeEnvironment env{};
    env.pid        = pid;
    env.exeName    = ProcessImageName(pid);
    env.imageName  = env.exeName;
    env.moduleBase = MainModuleBase(pid);
    env.osVersion  = OsVersionText();
    env.cpu        = CpuText();

    bool advapi32WasLoaded = false;
    env.hvci = HvciText(advapi32WasLoaded);
    env.advapi32State = advapi32WasLoaded
        ? "already loaded (probe added no module)"
        : "absent - loaded by probe (one extra module in this process)";

    CollectModules(pid, env);
    return env;
}

ProbeEnvironment AcgProbe::DescribeSelf() {
    return DescribeProcess(GetCurrentProcessId());
}

// ============================================================================
// Internal probes (run inside the game process)
// ============================================================================
const ULONG kStubMagic = 0xA5C0DE11;

bool ExecuteStubAt(void* address, ULONG magic, std::string& detail) {
    const ULONG observed = RunReturnStub(address);
    if (observed != magic) {
        detail = "stub returned " + Hex(observed) + " (expected the magic value)";
        return false;
    }
    return true;
}

void WriteReturnStub(void* address) {
    unsigned char stub[8] = { 0xB8, 0, 0, 0, 0, 0xC3 };   // mov eax,imm32 ; ret
    std::memcpy(stub + 1, &kStubMagic, 4);
    std::memcpy(address, stub, sizeof(stub));
}

// Allocate RWX, write an executable stub, run it.  The most basic question:
// after Javelin, is PAGE_EXECUTE_READWRITE still alloctable at all?
ProbeResult ProbeAllocRwx() {
    void* region = VirtualAlloc(nullptr, kProbeSize, MEM_COMMIT | MEM_RESERVE,
                               kPageExecuteReadWrite);
    if (!region) {
        return MakeResult("I1_alloc_rwx", "VirtualAlloc RWX + execute", false,
                          0, GetLastError(), 0, kProbeSize,
                          "PAGE_EXECUTE_READWRITE allocation refused");
    }

    WriteReturnStub(region);
    std::string detail;
    const bool executed = ExecuteStubAt(region, kStubMagic, detail);
    const ULONGLONG address = reinterpret_cast<ULONGLONG>(region);
    VirtualFree(region, 0, MEM_RELEASE);

    return MakeResult("I1_alloc_rwx", "VirtualAlloc RWX + execute", executed,
                      0, executed ? 0 : GetLastError(), address, kProbeSize,
                      executed ? "allocated and executed in place" : detail);
}

// The KB's recommended workaround shape: allocate RW, write, then flip to RX.
ProbeResult ProbeAllocRwThenProtectRx() {
    void* region = VirtualAlloc(nullptr, kProbeSize, MEM_COMMIT | MEM_RESERVE, kPageReadWrite);
    if (!region) {
        return MakeResult("I2_alloc_rw_protect_rx",
                          "VirtualAlloc RW -> VirtualProtect RX + execute",
                          false, 0, GetLastError(), 0, kProbeSize, "RW allocation failed");
    }

    WriteReturnStub(region);

    DWORD oldProtect = 0;
    const bool protected_ = VirtualProtect(region, kProbeSize, kPageExecuteRead, &oldProtect) != FALSE;
    std::string detail = protected_ ? "RW->RX accepted" : "VirtualProtect(RX) refused";

    bool executed = false;
    if (protected_) executed = ExecuteStubAt(region, kStubMagic, detail);

    const ULONGLONG address = reinterpret_cast<ULONGLONG>(region);
    VirtualFree(region, 0, MEM_RELEASE);

    return MakeResult("I2_alloc_rw_protect_rx",
                      "VirtualAlloc RW -> VirtualProtect RX + execute",
                      protected_ && executed, 0, protected_ ? 0 : GetLastError(),
                      address, kProbeSize, detail);
}
// Allocate already-RX, flip to RW to write, back to RX.  This is the shape a
// manual mapper needs when the loader only accepts RX allocations.
ProbeResult ProbeAllocRxWriteBack() {
    void* region = VirtualAlloc(nullptr, kProbeSize, MEM_COMMIT | MEM_RESERVE, kPageExecuteRead);
    if (!region) {
        return MakeResult("I3_alloc_rx_write_back",
                          "VirtualAlloc RX -> VirtualProtect RW -> write -> RX",
                          false, 0, GetLastError(), 0, kProbeSize, "RX allocation failed");
    }

    DWORD oldProtect = 0;
    const bool writable = VirtualProtect(region, kProbeSize, kPageReadWrite, &oldProtect) != FALSE;
    std::string detail = writable ? "RX->RW accepted" : "VirtualProtect(RW) refused";

    bool executed = false;
    if (writable) {
        WriteReturnStub(region);

        DWORD ignored = 0;
        const bool backToRx = VirtualProtect(region, kProbeSize, kPageExecuteRead, &ignored) != FALSE;
        if (backToRx) {
            executed = ExecuteStubAt(region, kStubMagic, detail);
            if (executed) detail = "RX->RW->write->RX round trip executed";
        } else {
            detail = "second VirtualProtect(RX) refused";
        }
    }

    const ULONGLONG address = reinterpret_cast<ULONGLONG>(region);
    VirtualFree(region, 0, MEM_RELEASE);

    return MakeResult("I3_alloc_rx_write_back",
                      "VirtualAlloc RX -> VirtualProtect RW -> write -> RX",
                      executed, 0, executed ? 0 : GetLastError(), address, kProbeSize, detail);
}

// Direct Nt* path: bypasses kernel32/kernelbase wrappers and any usermode hook
// an AC may have put on VirtualAlloc/VirtualProtect.
ProbeResult ProbeNtAllocateRwx() {
    NtAllocateVirtualMemoryFn ntAllocate = NtAllocateVirtualMemory();
    if (!ntAllocate) {
        return MakeResult("I4_nt_alloc_rwx", "ntdll!NtAllocateVirtualMemory RWX + execute",
                          false, 0, 0, 0, kProbeSize,
                          "ntdll!NtAllocateVirtualMemory not resolvable");
    }

    PVOID base = nullptr;
    SIZE_T size = kProbeSize;
    const LONG status = ntAllocate(GetCurrentProcess(), &base, 0, &size,
                                   MEM_COMMIT | MEM_RESERVE, kPageExecuteReadWrite);
    if (status != 0 || !base) {
        return MakeResult("I4_nt_alloc_rwx", "ntdll!NtAllocateVirtualMemory RWX + execute",
                          false, status, 0, 0, kProbeSize, "NTSTATUS " + StatusText(status));
    }

    WriteReturnStub(base);
    std::string detail;
    const bool executed = ExecuteStubAt(base, kStubMagic, detail);
    const ULONGLONG address = reinterpret_cast<ULONGLONG>(base);

    PVOID release = base;
    SIZE_T releaseSize = 0;
    ntAllocate(GetCurrentProcess(), &release, 0, &releaseSize, MEM_RELEASE, kPageReadOnly);

    return MakeResult("I4_nt_alloc_rwx", "ntdll!NtAllocateVirtualMemory RWX + execute",
                      executed, status, executed ? 0 : GetLastError(), address, kProbeSize,
                      executed ? "native RWX allocation executed in place" : detail);
}
// Re-protect a page of OUR OWN image (the game's image when injected).  A
// vtable/trampoline patch does exactly this, and AGC treats image pages
// differently from private allocations, so it must be measured separately.
ProbeResult ProbeNtProtectOwnImagePage() {
    NtProtectVirtualMemoryFn ntProtect = NtProtectVirtualMemory();
    HMODULE self = GetModuleHandleA(nullptr);
    if (!ntProtect || !self) {
        return MakeResult("I5_nt_protect_own_image",
                          "ntdll!NtProtectVirtualMemory on own image base -> RWX -> restore",
                          false, 0, 0, reinterpret_cast<ULONGLONG>(self), 0,
                          "ntdll!NtProtectVirtualMemory or module base unavailable");
    }

    PVOID page = self;
    SIZE_T size = kProbeSize;
    ULONG oldProtect = 0;
    const LONG status = ntProtect(GetCurrentProcess(), &page, &size,
                                  kPageExecuteReadWrite, &oldProtect);
    const ULONGLONG address = reinterpret_cast<ULONGLONG>(self);

    if (status != 0) {
        return MakeResult("I5_nt_protect_own_image",
                          "ntdll!NtProtectVirtualMemory on own image base -> RWX -> restore",
                          false, status, 0, address, kProbeSize,
                          "NTSTATUS " + StatusText(status) + " => VMT patching blocked");
    }

    PVOID again = self;
    SIZE_T againSize = kProbeSize;
    ULONG restoredProtect = 0;
    const LONG restoreStatus = ntProtect(GetCurrentProcess(), &again, &againSize,
                                         oldProtect ? oldProtect : kPageReadOnly,
                                         &restoredProtect);

    return MakeResult("I5_nt_protect_own_image",
                      "ntdll!NtProtectVirtualMemory on own image base -> RWX -> restore",
                      restoreStatus == 0, restoreStatus, 0, address, kProbeSize,
                      restoreStatus == 0
                        ? "image page re-protected and restored => VMT/trampoline patching viable"
                        : "RWX accepted but restore failed (page left RWX)");
}

// Section mapping: closest usermode-only approximation of the MDL/VAD-less path.
// Also records what the process itself reports for the region, because the
// MEM_MAPPED vs MEM_PRIVATE difference is exactly what a VAD scan looks at.
ProbeResult ProbeSectionMap() {
    NtCreateSectionFn createSection = NtCreateSection();
    NtMapViewOfSectionFn mapView   = NtMapViewOfSection();
    NtUnmapViewOfSectionFn unmap   = NtUnmapViewOfSection();
    if (!createSection || !mapView || !unmap) {
        return MakeResult("I6_section_map", "NtCreateSection + NtMapViewOfSection RWX + execute",
                          false, 0, 0, 0, kProbeSize, "section APIs unavailable in ntdll");
    }

    HANDLE section = nullptr;
    LARGE_INTEGER sectionSize{};
    sectionSize.QuadPart = static_cast<LONGLONG>(kProbeSize);

    LONG status = createSection(&section, SECTION_ALL_ACCESS, nullptr, &sectionSize,
                                PAGE_EXECUTE_READWRITE, SEC_COMMIT, nullptr);
    if (status != 0 || !section) {
        return MakeResult("I6_section_map", "NtCreateSection + NtMapViewOfSection RWX + execute",
                          false, status, 0, 0, kProbeSize,
                          "NtCreateSection NTSTATUS " + StatusText(status));
    }

    PVOID view = nullptr;
    SIZE_T viewSize = 0;
    status = mapView(section, GetCurrentProcess(), &view, 0, 0, nullptr, &viewSize,
                     kViewUnmap, 0, PAGE_EXECUTE_READWRITE);
    if (status != 0 || !view) {
        CloseHandle(section);
        return MakeResult("I6_section_map", "NtCreateSection + NtMapViewOfSection RWX + execute",
                          false, status, 0, 0, kProbeSize,
                          "NtMapViewOfSection NTSTATUS " + StatusText(status));
    }

    WriteReturnStub(view);
    std::string detail;
    const bool executed = ExecuteStubAt(view, kStubMagic, detail);
    const ULONGLONG address = reinterpret_cast<ULONGLONG>(view);
    if (executed) detail = "section-mapped memory executed in place";

    MEMORY_BASIC_INFORMATION mbi{};
    if (VirtualQuery(view, &mbi, sizeof(mbi)) == sizeof(mbi)) {
        char typeText[48] = { 0 };
        sprintf_s(typeText, sizeof(typeText), " | region type=0x%lX",
                  static_cast<unsigned long>(mbi.Type));
        detail += typeText;
        detail += (mbi.Type == MEM_MAPPED) ? " (MEM_MAPPED: section-backed)"
                                           : " (NOT MEM_MAPPED - recheck expectations)";
    }

    unmap(GetCurrentProcess(), view);
    CloseHandle(section);

    return MakeResult("I6_section_map", "NtCreateSection + NtMapViewOfSection RWX + execute",
                      executed, 0, executed ? 0 : GetLastError(), address, kProbeSize, detail);
}
// Informational: what is actually mapped in the target.  Reference integrity
// (1.3) reads this: d3d11 must be present by the time we hook Present, d3d9 must
// NOT be unless the fallback is deliberately taken, d3d12 tells us whether the
// DX12 overlay work (PHASE 4) is even reachable on this install.
ProbeResult ProbeInventory(DWORD pid, bool self) {
    ProbeEnvironment env = self ? AcgProbe::DescribeSelf()
                                : AcgProbe::DescribeProcess(pid);

    char buffer[512] = { 0 };
    sprintf_s(buffer, sizeof(buffer),
              "image=%s modules=%d d3d11=%s dxgi=%s d3d12=%s d3d9=%s d3dcompiler=%s os=%s hvci=%s",
              env.imageName.c_str(), env.moduleCount,
              ModulePresenceText(env.d3d11Loaded, env.moduleCount).c_str(),
              ModulePresenceText(env.dxgiLoaded, env.moduleCount).c_str(),
              ModulePresenceText(env.d3d12Loaded, env.moduleCount).c_str(),
              ModulePresenceText(env.d3d9Loaded, env.moduleCount).c_str(),
              ModulePresenceText(env.d3dCompilerLoaded, env.moduleCount).c_str(),
              env.osVersion.c_str(), env.hvci.c_str());

    const bool plausible = (env.d3d11Loaded || env.d3d9Loaded || env.d3d12Loaded);
    const char* const tail = plausible
                                 ? ""
                                 : (env.moduleCount == 0
                                        ? " | module list UNREADABLE: presence is unknown, not absent"
                                        : " | no render backend mapped yet (hook this after the game shows a frame)");
    return MakeResult("I0_inventory", "module inventory / reference integrity", plausible,
                      0, 0, env.moduleBase, 0,
                      std::string(buffer) + tail);
}

std::vector<ProbeResult> AcgProbe::RunInternal() {
    std::vector<ProbeResult> results;
    results.push_back(ProbeInventory(GetCurrentProcessId(), true));
    results.push_back(ProbeAllocRwx());
    results.push_back(ProbeAllocRwThenProtectRx());
    results.push_back(ProbeAllocRxWriteBack());
    results.push_back(ProbeNtAllocateRwx());
    results.push_back(ProbeNtProtectOwnImagePage());
    results.push_back(ProbeSectionMap());
    return results;
}
// ============================================================================
// External probes (run from the launcher against a target PID)
// ============================================================================
// Right combinations injectors rely on, least to most privileged.  A
// Javelin/EAC-class AC is known to hand out a *reduced* handle; knowing exactly
// which mask survives is what decides whether the usermode ladder can run at
// all, or whether the driver (B3) has to do the work.  Measured, not assumed.
std::string OpenProcessRightsMatrix(DWORD pid) {
    struct RightProbe { const char* name; DWORD mask; };

    static const RightProbe probes[] = {
        { "QUERY_LIMITED",  PROCESS_QUERY_LIMITED_INFORMATION },
        { "VM_READ",        PROCESS_VM_READ },
        { "VM_WRITE|VM_OP", PROCESS_VM_WRITE | PROCESS_VM_OPERATION },
        { "CREATE_THREAD",  PROCESS_CREATE_THREAD },
        { "injector(ALL)",  PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION |
                            PROCESS_VM_OPERATION | PROCESS_VM_WRITE | PROCESS_VM_READ },
    };

    std::string report;
    for (size_t i = 0; i < sizeof(probes) / sizeof(probes[0]); ++i) {
        HANDLE handle = OpenProcess(probes[i].mask, FALSE, pid);
        report += probes[i].name;
        if (handle) {
            CloseHandle(handle);
            report += "=OK ";
        } else {
            report += "=DENIED(" + std::to_string(GetLastError()) + ") ";
        }
    }
    return report;
}

ProbeResult ProbeOpenTarget(DWORD pid, HANDLE& handleOut) {
    handleOut = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION |
                            PROCESS_VM_OPERATION | PROCESS_VM_WRITE | PROCESS_VM_READ,
                            FALSE, pid);
    return MakeResult("X1_open_process", "OpenProcess with injector rights",
                      handleOut != nullptr, 0, handleOut ? 0 : GetLastError(), 0, 0,
                      std::string(handleOut ? "handle acquired"
                                            : "OpenProcess refused (elevation / protected process?)") +
                          " | rights: " + OpenProcessRightsMatrix(pid));
}

ProbeResult ProbeExternalAllocRwx(HANDLE target) {
    void* region = VirtualAllocEx(target, nullptr, kProbeSize,
                                  MEM_COMMIT | MEM_RESERVE, kPageExecuteReadWrite);
    if (!region) {
        return MakeResult("X2_alloc_ex_rwx", "VirtualAllocEx RWX in target",
                          false, 0, GetLastError(), 0, kProbeSize,
                          "RWX remote allocation refused");
    }

    // Write-then-read-back proves the memory is really usable, not just reserved.
    unsigned char pattern[16] = { 0 };
    for (int i = 0; i < 16; ++i) pattern[i] = static_cast<unsigned char>(0xA0 + i);

    SIZE_T written = 0;
    const bool wrote = WriteProcessMemory(target, region, pattern, sizeof(pattern), &written) != FALSE;

    unsigned char readBack[16] = { 0 };
    SIZE_T read = 0;
    const bool readOk = wrote &&
        ReadProcessMemory(target, region, readBack, sizeof(readBack), &read) != FALSE;
    const bool matches = readOk && std::memcmp(pattern, readBack, sizeof(pattern)) == 0;

    const ULONGLONG address = reinterpret_cast<ULONGLONG>(region);
    VirtualFreeEx(target, region, 0, MEM_RELEASE);

    return MakeResult("X2_alloc_ex_rwx", "VirtualAllocEx RWX in target",
                      matches, 0, matches ? 0 : GetLastError(), address, kProbeSize,
                      matches ? "allocated, written and verified in target"
                              : "allocation ok but write/read-back failed");
}

ProbeResult ProbeExternalAllocRwProtectRx(HANDLE target) {
    void* region = VirtualAllocEx(target, nullptr, kProbeSize,
                                  MEM_COMMIT | MEM_RESERVE, kPageReadWrite);
    if (!region) {
        return MakeResult("X3_alloc_ex_rw_protect_rx",
                          "VirtualAllocEx RW + VirtualProtectEx RX in target",
                          false, 0, GetLastError(), 0, kProbeSize, "RW remote allocation refused");
    }

    DWORD oldProtect = 0;
    const bool protected_ = VirtualProtectEx(target, region, kProbeSize,
                                             kPageExecuteRead, &oldProtect) != FALSE;
    const ULONGLONG address = reinterpret_cast<ULONGLONG>(region);
    VirtualFreeEx(target, region, 0, MEM_RELEASE);

    return MakeResult("X3_alloc_ex_rw_protect_rx",
                      "VirtualAllocEx RW + VirtualProtectEx RX in target",
                      protected_, 0, protected_ ? 0 : GetLastError(), address, kProbeSize,
                      protected_ ? "RW->RX in target accepted"
                                 : "VirtualProtectEx(RX) refused in target");
}

ProbeResult ProbeExternalNtAlloc(HANDLE target) {
    NtAllocateVirtualMemoryFn ntAllocate = NtAllocateVirtualMemory();
    if (!ntAllocate) {
        return MakeResult("X4_nt_alloc_ex", "ntdll!NtAllocateVirtualMemory RWX in target",
                          false, 0, 0, 0, kProbeSize, "NtAllocateVirtualMemory unavailable");
    }

    PVOID base = nullptr;
    SIZE_T size = kProbeSize;
    const LONG status = ntAllocate(target, &base, 0, &size,
                                   MEM_COMMIT | MEM_RESERVE, kPageExecuteReadWrite);
    if (status != 0 || !base) {
        return MakeResult("X4_nt_alloc_ex", "ntdll!NtAllocateVirtualMemory RWX in target",
                          false, status, 0, 0, kProbeSize, "NTSTATUS " + StatusText(status));
    }

    const ULONGLONG address = reinterpret_cast<ULONGLONG>(base);
    PVOID release = base;
    SIZE_T releaseSize = 0;
    ntAllocate(target, &release, 0, &releaseSize, MEM_RELEASE, kPageReadOnly);

    return MakeResult("X4_nt_alloc_ex", "ntdll!NtAllocateVirtualMemory RWX in target",
                      true, status, 0, address, kProbeSize,
                      "native remote RWX allocation accepted (no kernel32 wrapper)");
}
// X5: the core of the A7/A8 primitive set, minus relocations.  Create a section,
// map it RWX into the target, write a stub that calls ExitThread, start a thread
// at it inside the target and wait for that thread to end.  If it ends, remote
// execution out of freshly mapped, never-LoadLibrary'd memory is PROVEN.
ProbeResult ProbeRemoteSectionExecute(HANDLE target) {
    NtCreateSectionFn createSection = NtCreateSection();
    NtMapViewOfSectionFn mapView   = NtMapViewOfSection();
    NtUnmapViewOfSectionFn unmap   = NtUnmapViewOfSection();
    NtCreateThreadExFn createThread = NtCreateThreadEx();
    if (!createSection || !mapView || !unmap || !createThread) {
        return MakeResult("X5_section_map_execute",
                          "map section RWX into target + execute there",
                          false, 0, 0, 0, kProbeSize, "section/thread APIs unavailable");
    }

    HANDLE section = nullptr;
    LARGE_INTEGER sectionSize{};
    sectionSize.QuadPart = static_cast<LONGLONG>(kProbeSize);

    LONG status = createSection(&section, SECTION_ALL_ACCESS, nullptr, &sectionSize,
                                PAGE_EXECUTE_READWRITE, SEC_COMMIT, nullptr);
    if (status != 0 || !section) {
        return MakeResult("X5_section_map_execute",
                          "map section RWX into target + execute there",
                          false, status, 0, 0, kProbeSize,
                          "NtCreateSection NTSTATUS " + StatusText(status));
    }

    PVOID view = nullptr;
    SIZE_T viewSize = 0;
    status = mapView(section, target, &view, 0, 0, nullptr, &viewSize,
                     kViewUnmap, 0, PAGE_EXECUTE_READWRITE);
    if (status != 0 || !view) {
        CloseHandle(section);
        return MakeResult("X5_section_map_execute",
                          "map section RWX into target + execute there",
                          false, status, 0, 0, kProbeSize,
                          "NtMapViewOfSection NTSTATUS " + StatusText(status));
    }

    const ULONGLONG address = reinterpret_cast<ULONGLONG>(view);

    // kernel32!ExitThread resolves identically in the target: same system DLL
    // build, and system DLLs share one image base across a session.
    unsigned char stub[32] = { 0 };
    BuildExitThreadStub(stub, ExitThreadAddress());

    SIZE_T written = 0;
    if (!WriteProcessMemory(target, view, stub, kStubSize, &written)) {
        unmap(target, view);
        CloseHandle(section);
        return MakeResult("X5_section_map_execute",
                          "map section RWX into target + execute there",
                          false, 0, GetLastError(), address, kProbeSize,
                          "stub could not be written into the mapped view");
    }

    HANDLE thread = nullptr;
    status = createThread(&thread, THREAD_ALL_ACCESS, nullptr, target, view, nullptr,
                          0, 0, 0, 0, nullptr);

    bool executed = false;
    std::string detail;
    if (status != 0 || !thread) {
        detail = "NtCreateThreadEx NTSTATUS " + StatusText(status);
    } else {
        const DWORD wait = WaitForSingleObject(thread, 5000);
        if (wait == WAIT_OBJECT_0) {
            DWORD exitCode = 0xFFFFFFFF;
            GetExitCodeThread(thread, &exitCode);
            executed = true;
            char text[96] = { 0 };
            sprintf_s(text, sizeof(text),
                      "remote thread ran in mapped section and exited (code %lu)",
                      static_cast<unsigned long>(exitCode));
            detail = text;
        } else {
            detail = "remote thread did not finish within 5s (wait=" + Hex(wait) + ")";
        }
        CloseHandle(thread);
    }

    unmap(target, view);
    CloseHandle(section);

    return MakeResult("X5_section_map_execute",
                      "map section RWX into target + execute there",
                      executed, status, executed ? 0 : GetLastError(), address, kProbeSize, detail);
}
// X6: plain remote thread creation, with a callback that cannot mask a failure
// (no payload, so a broken payload cannot be mistaken for a broken injector).
ProbeResult ProbeRemoteThread(HANDLE target) {
    NtCreateThreadExFn createThread = NtCreateThreadEx();
    const ULONGLONG exitThread = ExitThreadAddress();
    if (!createThread || !exitThread) {
        return MakeResult("X6_remote_thread", "NtCreateThreadEx at kernel32!ExitThread",
                          false, 0, 0, 0, 0, "NtCreateThreadEx or ExitThread unresolved");
    }

    HANDLE thread = nullptr;
    const LONG status = createThread(&thread, THREAD_ALL_ACCESS, nullptr, target,
                                     reinterpret_cast<PVOID>(exitThread), nullptr,
                                     0, 0, 0, 0, nullptr);
    bool executed = false;
    std::string detail = "NtCreateThreadEx NTSTATUS " + StatusText(status);

    if (status == 0 && thread) {
        const DWORD wait = WaitForSingleObject(thread, 5000);
        executed = (wait == WAIT_OBJECT_0);
        detail  = executed ? "remote thread created and exited as expected"
                           : ("remote thread created but wait returned " + Hex(wait));
        CloseHandle(thread);
    }

    return MakeResult("X6_remote_thread", "NtCreateThreadEx at kernel32!ExitThread",
                      executed, status, executed ? 0 : GetLastError(), exitThread, 0, detail);
}

// X7: APC into an existing thread — no new thread at all.  Delivery needs an
// alertable wait in the target, so queue success is reported separately from
// delivery: kernel32!Sleep is the callback because it is safe in any thread
// state and returns by itself.
ProbeResult ProbeApcQueue(DWORD pid) {
    typedef VOID (WINAPI *ApcFn)(ULONG_PTR);

    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return MakeResult("X7_apc_queue", "QueueUserAPC into an existing target thread",
                          false, 0, GetLastError(), 0, 0, "thread snapshot failed");
    }

    THREADENTRY32 entry{};
    entry.dwSize = sizeof(entry);

    HANDLE chosen = nullptr;
    DWORD  chosenId = 0;
    if (Thread32First(snapshot, &entry)) {
        do {
            if (entry.th32OwnerProcessID != pid) continue;
            HANDLE thread = OpenThread(THREAD_SET_CONTEXT | THREAD_QUERY_INFORMATION,
                                       FALSE, entry.th32ThreadID);
            if (!thread) continue;
            chosen   = thread;
            chosenId = entry.th32ThreadID;
            break;
        } while (Thread32Next(snapshot, &entry));
    }
    CloseHandle(snapshot);

    if (!chosen) {
        return MakeResult("X7_apc_queue", "QueueUserAPC into an existing target thread",
                          false, 0, GetLastError(), 0, 0, "no openable thread found");
    }

    ApcFn callback = reinterpret_cast<ApcFn>(
        GetProcAddress(GetModuleHandleA("kernel32.dll"), "Sleep"));
    const DWORD result = QueueUserAPC(reinterpret_cast<PAPCFUNC>(callback), chosen, 0);
    const DWORD error  = result ? 0 : GetLastError();
    CloseHandle(chosen);

    char text[144] = { 0 };
    if (result) {
        sprintf_s(text, sizeof(text),
                  "APC queued to thread %lu; runs at the target's next alertable wait",
                  static_cast<unsigned long>(chosenId));
    } else {
        sprintf_s(text, sizeof(text), "QueueUserAPC failed (tid %lu)",
                  static_cast<unsigned long>(chosenId));
    }

    return MakeResult("X7_apc_queue", "QueueUserAPC into an existing target thread",
                      result != 0, 0, error, 0, 0, text);
}

// ---------------------------------------------------------------------------
// X8: can we READ the target at all?
//
// A separate question from "can we allocate into it", and on 2026-10-26 the two
// answers differ: Javelin refused every remote allocation while OpenProcess with
// full injector rights succeeded.  The read path is what the whole BESIDE
// (external overlay) architecture stands on - if reads work, an external ESP is
// still viable even while the injection ladder is blocked, so it must be
// measured, not assumed.
// ---------------------------------------------------------------------------
ProbeResult ProbeReadTarget(HANDLE target) {
    // Canonical PROCESS_BASIC_INFORMATION: 48 bytes on x64 (ExitStatus + 4 pad,
    // PEB, AffinityMask, BasePriority + 4 pad, UniqueProcessId, ParentProcessId).
    // Getting this size wrong returns STATUS_INFO_LENGTH_MISMATCH (0xC0000004),
    // which reads like a denial but is our own bug - hence the explicit layout.
    struct BasicInfo {
        LONG      exitStatus;
        PVOID     pebBaseAddress;
        ULONG_PTR affinityMask;
        LONG      basePriority;
        ULONG_PTR uniqueProcessId;
        ULONG_PTR inheritedFromUniqueProcessId;
    };

    NtQueryInformationProcessFn query = NtQueryInformationProcess();
    BasicInfo info{};
    ULONG returned = 0;
    const LONG status = query ? query(target, 0 /*ProcessBasicInformation*/, &info,
                                      static_cast<ULONG>(sizeof(info)), &returned)
                              : 0xC0000001L;

    // Cross-check via psapi (a different kernel path, and on modern Windows a
    // kernel32 export, so resolving it with GetProcAddress keeps the IAT clean).
    EnumProcessModulesExFn enumModules =
        ResolveFrom<EnumProcessModulesExFn>("kernel32.dll", "EnumProcessModulesEx");

    HMODULE firstModule = nullptr;
    DWORD   moduleCount = 0;
    DWORD   psapiError  = 0;
    if (enumModules) {
        HMODULE modules[16] = { 0 };
        DWORD needed = 0;
        if (enumModules(target, modules, sizeof(modules), &needed, 0x03 /*LIST_MODULES_ALL*/)) {
            firstModule = modules[0];
            moduleCount = needed / static_cast<DWORD>(sizeof(HMODULE));
        } else {
            psapiError = GetLastError();
        }
    }

    // Read the PEB (if we got one) ...
    PVOID imageBase = nullptr;
    SIZE_T read = 0;
    const bool pebRead = (status == 0 && info.pebBaseAddress != nullptr) &&
        ReadProcessMemory(target, info.pebBaseAddress, &imageBase, sizeof(imageBase), &read) != FALSE;

    // ... and independently read the module base psapi reported, which needs no
    // PEB at all.  Two independent read tests, so one failure cannot fake a
    // "reads are broken" verdict.
    DWORD probeWord = 0;
    const bool baseRead = firstModule &&
        ReadProcessMemory(target, firstModule, &probeWord, sizeof(probeWord), &read) != FALSE;

    const ULONGLONG base = (pebRead && imageBase)
                               ? reinterpret_cast<ULONGLONG>(imageBase)
                               : reinterpret_cast<ULONGLONG>(firstModule);

    bool mzOk = false;
    ULONGLONG regionSize = 0;
    DWORD protect = 0;
    DWORD vqeError = 0;
    if (base != 0) {
        IMAGE_DOS_HEADER dos{};
        if (ReadProcessMemory(target, reinterpret_cast<LPCVOID>(base), &dos, sizeof(dos), &read) &&
            dos.e_magic == IMAGE_DOS_SIGNATURE) {
            mzOk = true;
        }

        MEMORY_BASIC_INFORMATION mbi{};
        if (VirtualQueryEx(target, reinterpret_cast<LPCVOID>(base), &mbi, sizeof(mbi)) == sizeof(mbi)) {
            regionSize = static_cast<ULONGLONG>(mbi.RegionSize);
            protect = mbi.Protect;
        } else {
            vqeError = GetLastError();
        }
    }

    char detail[256] = { 0 };
    sprintf_s(detail, sizeof(detail),
              "native=%s peb=%s pebRead=%s psapi=%s base=%s baseRead=%s MZ=%s VQE=%s",
              StatusText(status).c_str(),
              info.pebBaseAddress ? Hex(reinterpret_cast<ULONGLONG>(info.pebBaseAddress)).c_str()
                                  : "none",
              pebRead ? "ok" : "no",
              psapiError ? ("DENIED(" + std::to_string(psapiError) + ")").c_str()
                         : ("modules=" + std::to_string(moduleCount)).c_str(),
              base ? Hex(base).c_str() : "none",
              baseRead ? "ok" : "no",
              mzOk ? "ok" : "no",
              vqeError == 0 ? "ok" : "failed");

    char full[384] = { 0 };
    sprintf_s(full, sizeof(full), "%s protect=0x%lX regionSize=0x%llX", detail,
              static_cast<unsigned long>(protect),
              static_cast<unsigned long long>(regionSize));

    return MakeResult("X8_read_target", "read target: PEB, module base, VirtualQueryEx",
                      mzOk || baseRead, status, psapiError ? psapiError : vqeError,
                      base, 0, full);
}

std::vector<ProbeResult> AcgProbe::RunExternal(DWORD pid) {
    std::vector<ProbeResult> results;
    results.push_back(ProbeInventory(pid, false));

    HANDLE target = nullptr;
    results.push_back(ProbeOpenTarget(pid, target));

    if (!target) {
        // Without a handle every remaining probe is unanswerable; say so instead
        // of reporting a wall of identical failures.
        results.push_back(MakeResult("X2_alloc_ex_rwx", "VirtualAllocEx RWX in target",
                                     false, 0, 0, 0, 0, "skipped: no target handle"));
        return results;
    }

    results.push_back(ProbeReadTarget(target));
    results.push_back(ProbeExternalAllocRwx(target));
    results.push_back(ProbeExternalAllocRwProtectRx(target));
    results.push_back(ProbeExternalNtAlloc(target));
    results.push_back(ProbeRemoteSectionExecute(target));
    results.push_back(ProbeRemoteThread(target));
    results.push_back(ProbeApcQueue(pid));

    CloseHandle(target);
    return results;
}
// ============================================================================
// Reporting
// ============================================================================
std::string AcgProbe::FormatEnvironment(const ProbeEnvironment& env) {
    char buffer[768] = { 0 };
    sprintf_s(buffer, sizeof(buffer),
              "pid=%lu image=%s base=0x%llX modules=%d\n"
              "os=%s hvci=%s cpu=%s advapi32=%s\n"
              "d3d11=%s dxgi=%s d3d12=%s d3d9=%s d3dcompiler=%s",
              static_cast<unsigned long>(env.pid), env.imageName.c_str(),
              static_cast<unsigned long long>(env.moduleBase), env.moduleCount,
              env.osVersion.c_str(), env.hvci.c_str(), env.cpu.c_str(),
              env.advapi32State.c_str(),
              ModulePresenceText(env.d3d11Loaded, env.moduleCount).c_str(),
              ModulePresenceText(env.dxgiLoaded, env.moduleCount).c_str(),
              ModulePresenceText(env.d3d12Loaded, env.moduleCount).c_str(),
              ModulePresenceText(env.d3d9Loaded, env.moduleCount).c_str(),
              ModulePresenceText(env.d3dCompilerLoaded, env.moduleCount).c_str());
    return std::string(buffer);
}

std::string AcgProbe::FormatReport(const std::string& title,
                                   const ProbeEnvironment& env,
                                   const std::vector<ProbeResult>& results) {
    std::string report;
    report += "==========================================================================\n";
    report += "ACG / INJECTION PROBE REPORT - " + title + "\n";
    report += "==========================================================================\n";
    report += "environment:\n" + FormatEnvironment(env) + "\n\n";
    report += "probes:\n";

    int passed = 0;
    for (std::size_t i = 0; i < results.size(); ++i) {
        const ProbeResult& probe = results[i];
        if (probe.passed) ++passed;

        char line[256] = { 0 };
        sprintf_s(line, sizeof(line), "  [%s] %-22s %s",
                  probe.passed ? "PASS" : "FAIL", probe.id.c_str(), probe.title.c_str());
        report += line;
        report += "\n";

        char facts[256] = { 0 };
        sprintf_s(facts, sizeof(facts),
                  "        address=0x%llX size=0x%llX status=%s win32Err=%lu",
                  static_cast<unsigned long long>(probe.address),
                  static_cast<unsigned long long>(probe.size),
                  StatusText(probe.status).c_str(),
                  static_cast<unsigned long>(probe.win32Error));
        report += facts;
        report += "\n";
        if (!probe.detail.empty()) report += "        detail: " + probe.detail + "\n";
    }

    char summary[128] = { 0 };
    sprintf_s(summary, sizeof(summary), "\n%d/%d probes passed\n",
              passed, static_cast<int>(results.size()));
    report += summary;
    report += "recommendation: " + Recommendation(results) + "\n";
    report += "==========================================================================\n";
    report += "END OF PROBE REPORT\n";
    report += "==========================================================================\n";
    return report;
}
std::string AcgProbe::Recommendation(const std::vector<ProbeResult>& results) {
    bool allocRwx = false, allocRwRx = false, imageProtect = false;
    bool sectionMap = false, remoteThread = false, apc = false;
    bool opened = false, readTarget = false;

    for (std::size_t i = 0; i < results.size(); ++i) {
        const ProbeResult& probe = results[i];
        if (probe.id == "I1_alloc_rwx")            allocRwx     = probe.passed;
        if (probe.id == "I2_alloc_rw_protect_rx")  allocRwRx    = probe.passed;
        if (probe.id == "I5_nt_protect_own_image") imageProtect = probe.passed;
        if (probe.id == "X1_open_process")         opened       = probe.passed;
        if (probe.id == "X5_section_map_execute")  sectionMap   = probe.passed;
        if (probe.id == "X6_remote_thread")        remoteThread = probe.passed;
        if (probe.id == "X7_apc_queue")            apc          = probe.passed;
        if (probe.id == "X8_read_target")          readTarget   = probe.passed;
    }

    std::string text;
    if (!opened) {
        text += "the target refused a handle => no user-mode strategy can run until the "
                "elevation/rights problem is solved. ";
    } else if (!allocRwx && !allocRwRx && !sectionMap) {
        text += "no remote ALLOCATION primitive works => the user-mode ladder (A1/A2/A3) cannot "
                "run as written; put B3 (driver maps from kernel context) first and treat A7/A8 "
                "as gated until the allocation path opens. ";
    }
    if (readTarget) {
        text += "READS work => the BESIDE/external reader path is still viable. ";
    } else if (opened && !readTarget) {
        text += "reads fail too => even an external overlay needs the driver. ";
    }
    if (sectionMap) {
        text += "section-map + remote execution WORK here => the A7 (manual map) rung is "
                "worth building; A8 (VAD-less/MDL) stays the stretch goal. ";
    }
    if (!allocRwx && allocRwRx) {
        text += "RWX allocation is refused but RW+VirtualProtect(RX) works => build the mapper "
                "as 'allocate RW, write, protect RX'. ";
    }
    if (!imageProtect) {
        text += "protecting our own image page failed => vtable/trampoline patching must use "
                "the RW+protect path. ";
    }
    if (remoteThread) text += "NtCreateThreadEx (A2) works => keep it as the ladder fallback. ";
    if (apc)          text += "APC queue (A3) queues => keep it as the low-footprint option. ";
    if (text.empty()) text = "no probe passed: re-run against the live game and check elevation.";
    return text;
}

std::string AcgProbe::DefaultReportPath(const char* tag) {
    char tempDirectory[MAX_PATH] = { 0 };
    if (GetTempPathA(MAX_PATH, tempDirectory) == 0) return std::string("acg_probe.txt");

    SYSTEMTIME now{};
    GetLocalTime(&now);

    char buffer[MAX_PATH * 2] = { 0 };
    sprintf_s(buffer, sizeof(buffer),
              "%sapexcheat_acg_probe_%s_%lu_%04u%02u%02u_%02u%02u%02u.txt",
              tempDirectory, tag ? tag : "run",
              static_cast<unsigned long>(GetCurrentProcessId()),
              static_cast<unsigned>(now.wYear),  static_cast<unsigned>(now.wMonth),
              static_cast<unsigned>(now.wDay),   static_cast<unsigned>(now.wHour),
              static_cast<unsigned>(now.wMinute), static_cast<unsigned>(now.wSecond));
    return std::string(buffer);
}

bool AcgProbe::WriteReportFile(const std::string& path, const std::string& title,
                               const ProbeEnvironment& env,
                               const std::vector<ProbeResult>& results,
                               std::string& errorOut) {
    const std::string report = FormatReport(title, env, results);

    std::FILE* file = nullptr;
    if (fopen_s(&file, path.c_str(), "wb") != 0 || !file) {
        errorOut = "could not open report file: " + path;
        return false;
    }

    const std::size_t written = std::fwrite(report.data(), 1, report.size(), file);
    std::fclose(file);

    if (written != report.size()) {
        errorOut = "short write to report file: " + path;
        return false;
    }

    errorOut.clear();
    return true;
}
