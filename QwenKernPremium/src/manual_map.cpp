#include "manual_map.h"

#include <tlhelp32.h>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {

// ---------------------------------------------------------------------------
// Small helpers.  kernel32 only: GATE 0 asserts the launcher's static IAT is
// { ADVAPI32, KERNEL32 }, so nothing here may pull in a new import library.
// ---------------------------------------------------------------------------

bool ReadWholeFile(const std::string& path, std::vector<BYTE>& out) {
    HANDLE file = CreateFileA(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                              OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;

    LARGE_INTEGER size{};
    bool ok = false;

    if (GetFileSizeEx(file, &size) && size.QuadPart > 0 &&
        size.QuadPart <= (64LL << 20)) {
        out.resize(static_cast<size_t>(size.QuadPart));

        DWORD read = 0;
        if (ReadFile(file, out.data(), static_cast<DWORD>(out.size()), &read, nullptr) &&
            static_cast<size_t>(read) == out.size()) {
            ok = true;
        }
    }

    CloseHandle(file);
    return ok;
}

ULONGLONG ModuleBaseInTarget(DWORD pid, const char* moduleName) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;

    MODULEENTRY32 entry{};
    entry.dwSize = sizeof(entry);

    ULONGLONG base = 0;
    if (Module32First(snapshot, &entry)) {
        do {
            if (_stricmp(entry.szModule, moduleName) == 0) {
                base = reinterpret_cast<ULONGLONG>(entry.modBaseAddr);
                break;
            }
        } while (Module32Next(snapshot, &entry));
    }

    CloseHandle(snapshot);
    return base;
}

bool ModuleLoadedInTarget(DWORD pid, const char* moduleName) {
    return ModuleBaseInTarget(pid, moduleName) != 0;
}

std::string WithWin32Error(const char* what, DWORD error) {
    char buffer[160] = { 0 };
    sprintf_s(buffer, sizeof(buffer), "%s failed: win32error=%lu", what,
              static_cast<unsigned long>(error));
    return std::string(buffer);
}

// LoadLibraryA inside the target, used only for DEPENDENCIES of the payload
// (a DLL the game loads itself).  The payload itself is never LoadLibrary'd -
// that is the whole point of A7.
bool PreloadDependency(DWORD pid, const std::string& moduleName, std::string& error) {
    HANDLE process = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_VM_OPERATION |
                                     PROCESS_VM_WRITE | PROCESS_QUERY_INFORMATION,
                                 FALSE, pid);
    if (!process) {
        error = WithWin32Error("OpenProcess (dependency preload)", GetLastError());
        return false;
    }

    const size_t size = moduleName.size() + 1;
    void* remoteName = VirtualAllocEx(process, nullptr, size, MEM_COMMIT | MEM_RESERVE,
                                      PAGE_READWRITE);
    if (!remoteName) {
        error = WithWin32Error("VirtualAllocEx (dependency name)", GetLastError());
        CloseHandle(process);
        return false;
    }

    SIZE_T written = 0;
    if (!WriteProcessMemory(process, remoteName, moduleName.c_str(), size, &written)) {
        error = WithWin32Error("WriteProcessMemory (dependency name)", GetLastError());
        VirtualFreeEx(process, remoteName, 0, MEM_RELEASE);
        CloseHandle(process);
        return false;
    }

    HMODULE kernel32 = GetModuleHandleA("kernel32.dll");
    const ULONGLONG localKernel32 = reinterpret_cast<ULONGLONG>(kernel32);
    const ULONGLONG localLoadLibrary =
        reinterpret_cast<ULONGLONG>(GetProcAddress(kernel32, "LoadLibraryA"));
    const ULONGLONG targetKernel32 = ModuleBaseInTarget(pid, "kernel32.dll");

    if (localLoadLibrary == 0 || targetKernel32 == 0) {
        error = "LoadLibraryA/kernel32 base unavailable (target module list unreadable)";
        VirtualFreeEx(process, remoteName, 0, MEM_RELEASE);
        CloseHandle(process);
        return false;
    }

    const ULONGLONG remoteLoadLibrary = targetKernel32 + (localLoadLibrary - localKernel32);

    HANDLE thread = CreateRemoteThread(
        process, nullptr, 0,
        reinterpret_cast<LPTHREAD_START_ROUTINE>(
            static_cast<ULONG_PTR>(remoteLoadLibrary)),
        remoteName, 0, nullptr);

    if (!thread) {
        error = WithWin32Error("CreateRemoteThread (dependency preload)", GetLastError());
        VirtualFreeEx(process, remoteName, 0, MEM_RELEASE);
        CloseHandle(process);
        return false;
    }

    const DWORD wait = WaitForSingleObject(thread, 10000);
    DWORD exitCode = 0;
    GetExitCodeThread(thread, &exitCode);

    CloseHandle(thread);
    VirtualFreeEx(process, remoteName, 0, MEM_RELEASE);
    CloseHandle(process);

    if (wait != WAIT_OBJECT_0) {
        error = "dependency preload thread did not finish in 10s";
        return false;
    }
    if (exitCode == 0) {
        error = "LoadLibraryA(" + moduleName + ") returned NULL in the target";
        return false;
    }
    return true;
}

} // namespace

namespace {

// ---------------------------------------------------------------------------
// Export resolution.  We resolve an IAT slot by asking the LOCAL copy of the
// same DLL "where is this export", then adding the TARGET's module base: system
// DLLs map at different bases per process, but the RVA is identical.
// ---------------------------------------------------------------------------

struct ExportLookup {
    DWORD       rva = 0;
    std::string forwarder;   // "OTHER.Func" when the export is a forwarder
};

IMAGE_NT_HEADERS64* NtHeadersOf(BYTE* localBase) {
    auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(localBase);
    return reinterpret_cast<IMAGE_NT_HEADERS64*>(localBase + dos->e_lfanew);
}

ExportLookup MakeLookup(BYTE* localBase, DWORD rva, const IMAGE_DATA_DIRECTORY& dir) {
    ExportLookup lookup;
    lookup.rva = rva;

    // A forwarder is an RVA inside the export directory whose target is a
    // "DLL.Function" string instead of code.
    if (rva >= dir.VirtualAddress && rva < dir.VirtualAddress + dir.Size) {
        lookup.forwarder = reinterpret_cast<const char*>(localBase + rva);
    }
    return lookup;
}

ExportLookup FindExportByName(BYTE* localBase, const char* functionName) {
    auto* nt = NtHeadersOf(localBase);
    const IMAGE_DATA_DIRECTORY dir =
        nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT];
    if (dir.VirtualAddress == 0 || dir.Size == 0) return ExportLookup();

    auto* exports = reinterpret_cast<IMAGE_EXPORT_DIRECTORY*>(localBase + dir.VirtualAddress);
    auto* names = reinterpret_cast<DWORD*>(localBase + exports->AddressOfNames);
    auto* ordinals = reinterpret_cast<WORD*>(localBase + exports->AddressOfNameOrdinals);
    auto* functions = reinterpret_cast<DWORD*>(localBase + exports->AddressOfFunctions);

    for (DWORD i = 0; i < exports->NumberOfNames; ++i) {
        const char* candidate = reinterpret_cast<const char*>(localBase + names[i]);
        if (strcmp(candidate, functionName) != 0) continue;

        const WORD index = ordinals[i];
        if (index >= exports->NumberOfFunctions) return ExportLookup();
        return MakeLookup(localBase, functions[index], dir);
    }
    return ExportLookup();
}

ExportLookup FindExportByOrdinal(BYTE* localBase, WORD ordinal) {
    auto* nt = NtHeadersOf(localBase);
    const IMAGE_DATA_DIRECTORY dir =
        nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT];
    if (dir.VirtualAddress == 0 || dir.Size == 0) return ExportLookup();

    auto* exports = reinterpret_cast<IMAGE_EXPORT_DIRECTORY*>(localBase + dir.VirtualAddress);
    auto* functions = reinterpret_cast<DWORD*>(localBase + exports->AddressOfFunctions);

    if (ordinal < exports->Base) return ExportLookup();
    const DWORD index = static_cast<DWORD>(ordinal) - exports->Base;
    if (index >= exports->NumberOfFunctions) return ExportLookup();
    return MakeLookup(localBase, functions[index], dir);
}

// Resolve one import to an address valid inside `pid`, following forwarders
// (kernel32 -> kernelbase is the common case on modern Windows).
ULONGLONG ResolveImport(DWORD pid, const std::string& moduleName,
                        const char* functionName, WORD ordinal, bool byOrdinal,
                        std::string& error) {
    std::string module = moduleName;
    char function[256] = { 0 };
    if (functionName) strncpy_s(function, sizeof(function), functionName, _TRUNCATE);

    for (int depth = 0; depth < 8; ++depth) {
        if (module.find('.') == std::string::npos) module += ".dll";

        ULONGLONG base = ModuleBaseInTarget(pid, module.c_str());
        if (base == 0) {
            printf("[A7]       dependency %-14s absent in target -> LoadLibraryA\n",
                   module.c_str());
            std::string preloadError;
            if (!PreloadDependency(pid, module, preloadError)) {
                error = preloadError;
                return 0;
            }
            base = ModuleBaseInTarget(pid, module.c_str());
            if (base == 0) {
                error = "module base still unreadable after preload: " + module;
                return 0;
            }
        }

        HMODULE local = LoadLibraryA(module.c_str());
        if (!local) {
            error = "local LoadLibraryA(" + module + ") failed";
            return 0;
        }

        const ExportLookup lookup =
            byOrdinal ? FindExportByOrdinal(reinterpret_cast<BYTE*>(local), ordinal)
                      : FindExportByName(reinterpret_cast<BYTE*>(local), function);

        if (lookup.rva == 0) {
            char name[320] = { 0 };
            if (byOrdinal) sprintf_s(name, sizeof(name), "%s!#%u", module.c_str(), ordinal);
            else           sprintf_s(name, sizeof(name), "%s!%s", module.c_str(), function);
            error = std::string("export not found: ") + name;
            return 0;
        }
        if (lookup.forwarder.empty()) return base + lookup.rva;

        const size_t dot = lookup.forwarder.find('.');
        if (dot == std::string::npos || dot + 1 >= lookup.forwarder.size()) {
            error = "malformed forwarder: " + lookup.forwarder;
            return 0;
        }

        module = lookup.forwarder.substr(0, dot);
        const std::string forwarded = lookup.forwarder.substr(dot + 1);
        if (forwarded[0] == '#') {
            byOrdinal = true;
            ordinal = static_cast<WORD>(strtoul(forwarded.c_str() + 1, nullptr, 10));
        } else {
            byOrdinal = false;
            strncpy_s(function, sizeof(function), forwarded.c_str(), _TRUNCATE);
        }
    }

    error = "forwarder chain deeper than 8 hops";
    return 0;
}

bool FixupImports(DWORD pid, BYTE* image, IMAGE_NT_HEADERS64* nt, std::string& error) {
    const IMAGE_DATA_DIRECTORY dir =
        nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (dir.VirtualAddress == 0 || dir.Size == 0) return true;

    auto* descriptor = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(image + dir.VirtualAddress);
    for (; descriptor->Name != 0; ++descriptor) {
        const char* moduleName = reinterpret_cast<const char*>(image + descriptor->Name);

        auto* thunk = reinterpret_cast<IMAGE_THUNK_DATA64*>(image + descriptor->FirstThunk);
        auto* nameThunk = (descriptor->OriginalFirstThunk != 0)
                              ? reinterpret_cast<IMAGE_THUNK_DATA64*>(image + descriptor->OriginalFirstThunk)
                              : thunk;

        for (; nameThunk->u1.Function != 0; ++nameThunk, ++thunk) {
            const bool byOrdinal = (nameThunk->u1.Ordinal & IMAGE_ORDINAL_FLAG64) != 0;
            const char* functionName = "";
            WORD ordinal = 0;

            if (byOrdinal) {
                ordinal = static_cast<WORD>(nameThunk->u1.Ordinal & 0xFFFFu);
            } else {
                auto* import = reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(
                    image + nameThunk->u1.AddressOfData);
                functionName = reinterpret_cast<const char*>(import->Name);
            }

            const ULONGLONG address =
                ResolveImport(pid, moduleName, functionName, ordinal, byOrdinal, error);
            if (address == 0) return false;

            thunk->u1.Function = address;
        }
    }
    return true;
}

bool ApplyRelocations(BYTE* image, IMAGE_NT_HEADERS64* nt, ULONGLONG delta,
                      std::string& error) {
    if (delta == 0) return true;

    const IMAGE_DATA_DIRECTORY dir =
        nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC];
    if (dir.VirtualAddress == 0 || dir.Size == 0) return true;

    DWORD consumed = 0;
    while (consumed + sizeof(IMAGE_BASE_RELOCATION) <= dir.Size) {
        auto* block = reinterpret_cast<IMAGE_BASE_RELOCATION*>(
            image + dir.VirtualAddress + consumed);
        if (block->SizeOfBlock < sizeof(IMAGE_BASE_RELOCATION)) break;

        const DWORD count =
            (block->SizeOfBlock - sizeof(IMAGE_BASE_RELOCATION)) / sizeof(WORD);
        auto* entries = reinterpret_cast<WORD*>(
            reinterpret_cast<BYTE*>(block) + sizeof(IMAGE_BASE_RELOCATION));

        for (DWORD i = 0; i < count; ++i) {
            const WORD type = static_cast<WORD>(entries[i] >> 12);
            const WORD offset = static_cast<WORD>(entries[i] & 0x0FFFu);
            BYTE* target = image + block->VirtualAddress + offset;

            if (type == IMAGE_REL_BASED_DIR64) {
                *reinterpret_cast<ULONGLONG*>(target) += delta;
            } else if (type == IMAGE_REL_BASED_HIGHLOW) {
                *reinterpret_cast<DWORD*>(target) += static_cast<DWORD>(delta);
            } else if (type != IMAGE_REL_BASED_ABSOLUTE) {
                error = "unsupported relocation type in payload";
                return false;
            }
        }

        consumed += block->SizeOfBlock;
    }
    return true;
}

DWORD ProtectionFor(DWORD characteristics) {
    const bool execute = (characteristics & IMAGE_SCN_MEM_EXECUTE) != 0;
    const bool read    = (characteristics & IMAGE_SCN_MEM_READ) != 0;
    const bool write   = (characteristics & IMAGE_SCN_MEM_WRITE) != 0;

    if (execute && write) return PAGE_EXECUTE_READWRITE;
    if (execute)          return read ? PAGE_EXECUTE_READ : PAGE_EXECUTE;
    if (write)            return PAGE_READWRITE;
    return read ? PAGE_READONLY : PAGE_NOACCESS;
}

// The only in-target code A7 needs: call AddressOfEntryPoint(imageBase, 1, 0)
// and leave its BOOL in the thread exit code.
std::vector<BYTE> BuildEntryStub(ULONGLONG imageBase, ULONGLONG entryPoint) {
    std::vector<BYTE> code;
    const auto emit = [&code](std::initializer_list<BYTE> bytes) {
        code.insert(code.end(), bytes.begin(), bytes.end());
    };
    const auto emit64 = [&code](BYTE opcode1, BYTE opcode2, ULONGLONG value) {
        code.push_back(opcode1);
        code.push_back(opcode2);
        for (int i = 0; i < 8; ++i) {
            code.push_back(static_cast<BYTE>((value >> (8 * i)) & 0xFFu));
        }
    };

    emit({ 0x48, 0x83, 0xEC, 0x28 });                   // sub rsp, 0x28
    emit64(0x48, 0xB9, imageBase);                      // mov rcx, imageBase
    emit({ 0x48, 0xC7, 0xC2, 0x01, 0x00, 0x00, 0x00 }); // mov rdx, 1
    emit({ 0x45, 0x31, 0xC0 });                         // xor r8d, r8d
    emit64(0x48, 0xB8, entryPoint);                     // mov rax, entryPoint
    emit({ 0xFF, 0xD0 });                               // call rax
    emit({ 0x48, 0x83, 0xC4, 0x28 });                   // add rsp, 0x28
    emit({ 0xC3 });                                     // ret
    return code;
}

} // namespace

namespace ManualMapper {

MapResult Map(DWORD pid, const std::string& dllPath) {
    MapResult result;

    std::vector<BYTE> file;
    if (!ReadWholeFile(dllPath, file)) {
        result.error = "cannot read payload file: " + dllPath;
        return result;
    }
    if (file.size() < sizeof(IMAGE_DOS_HEADER)) {
        result.error = "payload is smaller than a DOS header";
        return result;
    }

    auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(file.data());
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) {
        result.error = "payload has no MZ signature";
        return result;
    }
    if (static_cast<size_t>(dos->e_lfanew) + sizeof(IMAGE_NT_HEADERS64) > file.size()) {
        result.error = "payload NT headers are outside the file";
        return result;
    }

    auto* nt = reinterpret_cast<IMAGE_NT_HEADERS64*>(file.data() + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) {
        result.error = "payload has no PE signature";
        return result;
    }
    if (nt->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64) {
        result.error = "payload is not x64";
        return result;
    }
    if ((nt->FileHeader.Characteristics & IMAGE_FILE_DLL) == 0) {
        result.error = "payload is not a DLL";
        return result;
    }

    const DWORD imageSize = nt->OptionalHeader.SizeOfImage;
    const ULONGLONG preferredBase = nt->OptionalHeader.ImageBase;
    const DWORD entryRva = nt->OptionalHeader.AddressOfEntryPoint;

    if (imageSize == 0 || entryRva == 0 || entryRva >= imageSize) {
        result.error = "payload has no usable image size / entry point";
        return result;
    }

    HANDLE process = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_VM_OPERATION |
                                     PROCESS_VM_WRITE | PROCESS_VM_READ |
                                     PROCESS_QUERY_INFORMATION,
                                 FALSE, pid);
    if (!process) {
        result.error = WithWin32Error("OpenProcess", GetLastError());
        return result;
    }

    void* remoteImage = VirtualAllocEx(process, nullptr, imageSize,
                                       MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remoteImage) {
        result.error = WithWin32Error("VirtualAllocEx(image)", GetLastError());
        CloseHandle(process);
        return result;
    }

    const ULONGLONG imageBase = reinterpret_cast<ULONGLONG>(remoteImage);
    printf("[A7]       image   : %lu bytes -> 0x%llX (preferred 0x%llX)\n",
           static_cast<unsigned long>(imageSize),
           static_cast<unsigned long long>(imageBase),
           static_cast<unsigned long long>(preferredBase));

    // ---- build the image locally ------------------------------------------
    std::vector<BYTE> image(imageSize, 0);
    const size_t headersSize = (nt->OptionalHeader.SizeOfHeaders < file.size())
                                   ? static_cast<size_t>(nt->OptionalHeader.SizeOfHeaders)
                                   : file.size();
    memcpy(image.data(), file.data(), headersSize);

    auto* mappedNt = reinterpret_cast<IMAGE_NT_HEADERS64*>(image.data() + dos->e_lfanew);
    IMAGE_SECTION_HEADER* section = IMAGE_FIRST_SECTION(mappedNt);
    for (WORD i = 0; i < mappedNt->FileHeader.NumberOfSections; ++i, ++section) {
        if (section->SizeOfRawData == 0) continue;

        const size_t offset = section->VirtualAddress;
        if (offset >= imageSize) continue;

        const size_t available = static_cast<size_t>(imageSize) - offset;
        const size_t copySize = (section->SizeOfRawData < available)
                                    ? static_cast<size_t>(section->SizeOfRawData)
                                    : available;
        if (copySize == 0) continue;
        if (static_cast<size_t>(section->PointerToRawData) + copySize > file.size()) continue;

        memcpy(image.data() + offset, file.data() + section->PointerToRawData, copySize);
    }

    std::string error;
    const ULONGLONG delta = imageBase - preferredBase;

    if (!ApplyRelocations(image.data(), mappedNt, delta, error)) {
        result.error = "relocations: " + error;
        VirtualFreeEx(process, remoteImage, 0, MEM_RELEASE);
        CloseHandle(process);
        return result;
    }
    printf("[A7]       relocs  : %s\n",
           delta == 0 ? "none (payload mapped at its preferred base)"
                      : "applied for the real load address");

    if (!FixupImports(pid, image.data(), mappedNt, error)) {
        result.error = "imports: " + error;
        VirtualFreeEx(process, remoteImage, 0, MEM_RELEASE);
        CloseHandle(process);
        return result;
    }
    printf("[A7]       imports : resolved against the target's module bases\n");

    SIZE_T written = 0;
    if (!WriteProcessMemory(process, remoteImage, image.data(), imageSize, &written) ||
        written != imageSize) {
        result.error = WithWin32Error("WriteProcessMemory(image)", GetLastError());
        VirtualFreeEx(process, remoteImage, 0, MEM_RELEASE);
        CloseHandle(process);
        return result;
    }

    // ---- per-section protections ------------------------------------------
    IMAGE_SECTION_HEADER* guardSection = IMAGE_FIRST_SECTION(mappedNt);
    for (WORD i = 0; i < mappedNt->FileHeader.NumberOfSections; ++i, ++guardSection) {
        const DWORD size = guardSection->Misc.VirtualSize != 0
                               ? guardSection->Misc.VirtualSize
                               : guardSection->SizeOfRawData;
        if (size == 0) continue;

        DWORD previous = 0;
        if (!VirtualProtectEx(process,
                              reinterpret_cast<BYTE*>(remoteImage) + guardSection->VirtualAddress,
                              size, ProtectionFor(guardSection->Characteristics),
                              &previous)) {
            result.error = WithWin32Error("VirtualProtectEx(section)", GetLastError());
            VirtualFreeEx(process, remoteImage, 0, MEM_RELEASE);
            CloseHandle(process);
            return result;
        }
    }

    DWORD previousHeaders = 0;
    VirtualProtectEx(process, remoteImage, headersSize, PAGE_READONLY, &previousHeaders);

    // ---- call the entry point ---------------------------------------------
    void* remoteStub = VirtualAllocEx(process, nullptr, 0x1000,
                                      MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!remoteStub) {
        result.error = WithWin32Error("VirtualAllocEx(entry stub)", GetLastError());
        VirtualFreeEx(process, remoteImage, 0, MEM_RELEASE);
        CloseHandle(process);
        return result;
    }

    const std::vector<BYTE> stub = BuildEntryStub(imageBase, imageBase + entryRva);
    if (!WriteProcessMemory(process, remoteStub, stub.data(), stub.size(), &written) ||
        written != stub.size()) {
        result.error = WithWin32Error("WriteProcessMemory(entry stub)", GetLastError());
        VirtualFreeEx(process, remoteStub, 0, MEM_RELEASE);
        VirtualFreeEx(process, remoteImage, 0, MEM_RELEASE);
        CloseHandle(process);
        return result;
    }
    FlushInstructionCache(process, remoteStub, stub.size());

    HANDLE thread = CreateRemoteThread(
        process, nullptr, 0,
        reinterpret_cast<LPTHREAD_START_ROUTINE>(remoteStub), nullptr, 0, nullptr);

    if (!thread) {
        result.error = WithWin32Error("CreateRemoteThread(entry stub)", GetLastError());
        VirtualFreeEx(process, remoteStub, 0, MEM_RELEASE);
        VirtualFreeEx(process, remoteImage, 0, MEM_RELEASE);
        CloseHandle(process);
        return result;
    }

    const DWORD wait = WaitForSingleObject(thread, 15000);
    DWORD exitCode = 0;
    GetExitCodeThread(thread, &exitCode);

    result.threadId      = GetThreadId(thread);
    result.imageBase     = imageBase;
    result.entryExecuted = (wait == WAIT_OBJECT_0 && exitCode != 0);
    result.success       = result.entryExecuted;

    if (!result.success) {
        char buffer[192] = { 0 };
        if (wait != WAIT_OBJECT_0) {
            sprintf_s(buffer, sizeof(buffer),
                      "entry thread did not finish in 15s (last code 0x%08lX)",
                      static_cast<unsigned long>(exitCode));
        } else {
            sprintf_s(buffer, sizeof(buffer), "entry point returned FALSE (0x%08lX)",
                      static_cast<unsigned long>(exitCode));
        }
        result.error = buffer;
    }

    printf("[A7]       entry   : thread %lu, exit 0x%08lX -> %s\n",
           static_cast<unsigned long>(result.threadId),
           static_cast<unsigned long>(exitCode),
           result.entryExecuted ? "DllMain chain executed" : "NO entry execution");

    CloseHandle(thread);
    VirtualFreeEx(process, remoteStub, 0, MEM_RELEASE);
    CloseHandle(process);

    return result;
}

} // namespace ManualMapper


