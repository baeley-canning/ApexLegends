#pragma once
#include <windows.h>
#include <string>
#include <vector>

// ============================================================================
// Apex Legends Anti-Cheat Evasion — Injection Methods
// Based on RE findings from JAVELIN and R5AC analysis docs
// ============================================================================

// ----------------------------------------------------------------------------
// Native API declarations
//
// winternl.h does NOT declare NtCreateThreadEx (unlike NtCreateThread), and
// "decltype(&NtCreateThreadEx)" therefore failed with C2065.  The signature
// below matches the NT native ABI (ntdll!NtCreateThreadEx, 11 arguments).
// ----------------------------------------------------------------------------
#ifndef _APEX_NTSTATUS_DEFINED
#define _APEX_NTSTATUS_DEFINED
#ifndef _NTSTATUS_DEFINED
typedef _Return_type_success_(return >= 0) LONG NTSTATUS;
typedef NTSTATUS *PNTSTATUS;
#endif
#endif

using NtCreateThreadEx_t = NTSTATUS (NTAPI*)(
    PHANDLE            ThreadHandle,
    ACCESS_MASK        DesiredAccess,
    PVOID              ObjectAttributes,
    HANDLE             ProcessHandle,
    PVOID              StartRoutine,
    PVOID              Argument,
    ULONG              CreateFlags,
    SIZE_T             ZeroBits,
    SIZE_T             StackSize,
    SIZE_T             MaximumStackSize,
    PVOID              AttributeList);

// Name kept for source compatibility with existing call sites.
using FNtCreateThreadEx = NtCreateThreadEx_t;

// APC callback type for queued LoadLibrary delivery (PAPCFUNC is already
// declared by winnt.h; the alias keeps existing code readable).
#ifndef _APEX_PAPCFUNC_DEFINED
#define _APEX_PAPCFUNC_DEFINED
typedef VOID (WINAPI *PAPCFUNC)(ULONG_PTR dwParam);
#endif


// Injection strategies exposed to the launcher.
//
// Values are stable (they are persisted in the launcher's sticky file), so new
// methods are APPENDED.  Codes are the ladder rungs from
// docs\INJECTION_MENU_AND_RISK_MATRIX.txt, so every log line lines up with the
// roadmap without a second naming scheme.
enum class InjectionMethod {
    NtCreateThreadEx   = 0,   // A2  "HIDE"        - usermode, native thread creation
    ApcQueue           = 1,   // A3  "IMPERSONATE" - usermode, APC into existing thread
    KernelDriver       = 2,   // B3  "KERNEL"      - driver launches the module
    CreateRemoteThread = 3,   // A1  baseline      - CRT + LoadLibraryA
    ManualMap          = 4,   // A7  "MANUAL"      - no loader, no PEB entry
    ThreadHijack       = 5,   // A4  "HIJACK"      - suspended thread, private stack
    VadLessMap         = 6    // A8  declared ladder rung, not implemented yet
};

// Human readable name of a method (launcher UI + logs), code prefixed.
const char* InjectionMethodName(InjectionMethod method);

// Ladder rung code ("A1".."A3", "B3").  Distinct from the name so logs can be
// parsed and compared against the roadmap table.
const char* InjectionMethodCode(InjectionMethod method);

// FALSE for the rungs the roadmap lists but this build does not implement yet
// (A4 thread hijack, A7 manual map, A8 VAD-less).  The ladder logs a SKIP for
// those instead of pretending they failed for a real reason.
bool InjectionMethodImplemented(InjectionMethod method);

struct InjectionResult {
    bool success;
    DWORD threadId;
    HMODULE dllBaseAddress;
    std::string errorMessage;

    // ---- ladder verdict plumbing (PHASE 1.2) ------------------------------
    // A loader-based rung (A1..A4) is only proven when the payload shows up in
    // the target's PEB module list.  A manual map (A7/A8) deliberately keeps the
    // image OUT of that list, so the ladder must verify the mapped image + a
    // completed entry-point call instead of calling a working rung a failure.
    bool moduleListVerdict = true;   // false => verify image at dllBaseAddress
    bool entryExecuted     = false;  // false => entry point never returned TRUE
};

class ApexInjector {
public:
    ApexInjector();
    ~ApexInjector() = default;

    // ---- Unified entry point used by the launcher -------------------------
    // Dispatches to the requested strategy. driverPath is only used by
    // KernelDriver (path to the companion .sys) - see kernel_injector.cpp.
    InjectionResult Inject(DWORD targetPid, const std::string& dllPath,
                           InjectionMethod method,
                           const std::string& driverPath = std::string());

    // ========================================================================
    // METHOD 1: NtCreateThreadEx — "HIDE" Strategy
    // Bypasses CreateRemoteThread hooks by using native NT API directly.
    // Targets Javelin's heuristic detection layer (monitors CRT functions).
    // R5AC relevance: produces cleaner stack traces than CRT functions,
    // stays within ntdll.dll whitelisted ranges (+1000 to +119f1e).
    // ========================================================================
    InjectionResult InjectViaNtCreateThreadEx(DWORD targetPid, const std::string& dllPath);

    // ========================================================================
    // METHOD 2: APC Queue — "IMPERSONATE" Strategy  
    // Queues LoadLibrary into an EXISTING game thread. Looks like legitimate 
    // game work. No new thread creation signature to detect.
    // Javelin relevance: bypasses thread enumeration checks (monitors NEW threads).
    // R5AC relevance: whitelisted thread already passes module whitelist check.
    // ========================================================================
    InjectionResult InjectViaApcQueue(DWORD targetPid, const std::string& dllPath);

    // ========================================================================
    // METHOD: CreateRemoteThread + LoadLibraryA — "A1" baseline
    // The weakest, most-signed-path-worn option, but it is the reference point
    // for the ladder: if this fails, nothing else will work either.
    // ========================================================================
    InjectionResult InjectViaCreateRemoteThread(DWORD targetPid, const std::string& dllPath);

    // ========================================================================
    // METHOD A4: Thread hijack — "HIJACK"
    // No new thread and no APC: suspend an existing thread, point it at a tiny
    // stub on a PRIVATE stack that calls LoadLibraryA, then let the stub restore
    // the saved CONTEXT (RtlRestoreContext) so the thread continues exactly
    // where it was.  Costs a full volatile+nonvolatile register save, which is
    // why the roadmap rates it "med" rather than "high".
    // ========================================================================
    InjectionResult InjectViaThreadHijack(DWORD targetPid, const std::string& dllPath);

    // ========================================================================
    // METHOD A7: Manual map — "MANUAL"
    // The payload is mapped by us (headers + sections + relocations + imports),
    // its entry point is called on a fresh thread, and it never enters the PEB
    // module list: no LoadLibrary of the payload, no loader lock, no LDR_DATA
    // entry for the AC to walk.  See src\manual_map.cpp for the mechanics and
    // the limits (dependencies are still LoadLibrary'd in the target).
    // ========================================================================
    InjectionResult InjectViaManualMap(DWORD targetPid, const std::string& dllPath);

    // ========================================================================
    // METHOD 3: Kernel driver - "KERNEL" Strategy
    // Installs + starts a companion kernel driver (apexdrv.sys) over the SCM and
    // hands it (PID, DLL path) through an IOCTL.  The driver performs the
    // mapping from kernel context (PsLookupProcessByProcessId + ZwCreateThreadEx),
    // so no usermode handle to r5apex.exe is ever opened and no usermode thread
    // is created - complementary to the two usermode strategies above.
    // ========================================================================
    InjectionResult InjectViaKernelDriver(DWORD targetPid, const std::string& dllPath,
                                          const std::string& driverPath);

    // ========================================================================
    // METHOD 3b: kernel reachability probe (no injection at all)
    // Starts the same driver, then asks it to repeat from kernel context what
    // the user-mode ladder cannot do on the live target: open with injector
    // rights, allocate, and copy the target's PEB out (MmCopyVirtualMemory).
    // Fills `report` with a line-per-step table and returns true when the
    // driver itself answered (a refused step is data, not a failure of this
    // call).  Answers Q10 of the PHASE 1 measurement record.
    // ========================================================================
    bool ProbeViaKernel(DWORD targetPid, const std::string& driverPath,
                        std::string& report);

    // Utility: enumerate all threads in a process (needed for APC targeting)
    std::vector<DWORD> EnumerateThreads(DWORD targetPid);

    // Utility: is `moduleName` loaded in `pid`?  The INJECTION VERDICT used by
    // the ladder: a strategy may return success and still fail to load the
    // payload, and only a module-list check settles it.
    static bool IsModuleLoaded(DWORD pid, const char* moduleName);

    // Utility: resolve NtCreateThreadEx from ntdll.dll at runtime
    static FNtCreateThreadEx ResolveNtCreateThreadEx();

private:
    // Internal helper: module base inside the target process (Toolhelp32 based)
    HMODULE GetModuleBase(DWORD pid, const char* moduleName);

    HANDLE hTargetProcess_;
};
