#pragma once
#include <windows.h>
#include <string>
#include <vector>

// ============================================================================
// acg_probe — PHASE 1.1 measurement harness
//
// WHY THIS EXISTS
//   docs\JAVELIN_2026_DETECTION_AND_INJECTION_REALITY.txt records (RE, 2026) that
//   AGC blocks ZwAllocateVirtualMemory(PAGE_EXECUTE*) / ZwProtectVirtualMemory
//   *inside* r5apex_dx12.exe.  Everything the roadmap builds on top of that -
//   the A7/A8 manual-mapper, the trampoline hooking in PHASE 4, the CRT-init
//   plan - depends on which of these primitives actually succeed on THIS
//   machine.  The KB says "AGC blocks it"; this harness turns that into numbers.
//
// TWO MODES, BOTH NEEDED
//   RunInternal() : runs inside r5apex_dx12.exe (called from Application::
//                   Initialize) and answers "what may OUR DLL do to the game
//                   process it already lives in?" — allocation, protection
//                   changes, section mapping, execute-in-place, VAD presence.
//   RunExternal() : runs in apex_launcher.exe against a target PID and answers
//                   "what may an injector do from outside?" — OpenProcess with
//                   each right combination injectors rely on, the READ path
//                   (PEB + image headers + VirtualQueryEx: what an external
//                   overlay lives on), then the delivery primitives:
//                   VirtualAllocEx(RWX / RW+protect), ntdll!NtAllocateVirtualMemory,
//                   remote section map + remote execution, NtCreateThreadEx, APC.
//
//   Nothing here touches game structures; it only measures loader/MM primitives,
//   so it is safe to run in a live match and against any target process (it
//   defaults to the launcher's own PID when no game is running).
//
// REPORT FORMAT
//   One line per probe with PASS/FAIL, the raw NTSTATUS/GetLastError, the
//   address, and a detail string.  The recommendation line at the end is what
//   the PHASE 1 ladder (1.2) is validated against — it is advisory text, the
//   ladder itself never reads it.
//
// IMPORTS
//   kernel32 + ntdll (resolved with GetProcAddress, so ntdll never becomes a
//   static import) + advapi32 (for the HVCI registry key, loaded lazily and only
//   if the process does not already have it).  GATE 0 asserts the static IAT.
// ============================================================================

struct ProbeResult {
    std::string  id;          // stable id, e.g. "I2_alloc_rw_then_protect_rx"
    std::string  title;       // human readable one-liner
    bool         passed;
    LONG         status;      // NTSTATUS of the native call (0 when n/a)
    DWORD        win32Error;  // GetLastError() when relevant (0 when n/a)
    ULONGLONG    address;     // where the allocation/mapping landed (0 when n/a)
    std::size_t  size;
    std::string  detail;      // protection, region type, failing reason, notes
};

struct ProbeEnvironment {
    std::string exeName;
    DWORD       pid;
    ULONGLONG   moduleBase;
    std::string imageName;      // module name the target really runs
    std::string osVersion;      // RtlGetVersion, not the GetVersionEx shim
    std::string hvci;           // "enabled" / "disabled" / "unknown"
    std::string cpu;            // vendor string + hypervisor-present bit
    std::string advapi32State;  // "already loaded" / "loaded by probe"
    bool        d3d11Loaded;
    bool        dxgiLoaded;
    bool        d3d12Loaded;
    bool        d3d9Loaded;
    bool        d3dCompilerLoaded;
    int         moduleCount;
};

class AcgProbe {
public:
    // Environment fingerprint — recorded with every report so a result is only
    // comparable against another result from the same machine state.
    static ProbeEnvironment DescribeSelf();
    static ProbeEnvironment DescribeProcess(DWORD pid);

    // Measurement runs.
    static std::vector<ProbeResult> RunInternal();
    static std::vector<ProbeResult> RunExternal(DWORD pid);

    // Reporting.
    static std::string FormatEnvironment(const ProbeEnvironment& env);
    static std::string FormatReport(const std::string& title,
                                    const ProbeEnvironment& env,
                                    const std::vector<ProbeResult>& results);
    static bool WriteReportFile(const std::string& path,
                                const std::string& title,
                                const ProbeEnvironment& env,
                                const std::vector<ProbeResult>& results,
                                std::string& errorOut);

    // Advisory: which injection strategy the measured results point at.
    static std::string Recommendation(const std::vector<ProbeResult>& results);

    // %TEMP%\apexcheat_acg_probe_<tag>_<pid>.txt — never the game directory
    // (Apex' own directory is not reliably writable for every install layout).
    static std::string DefaultReportPath(const char* tag);
};
