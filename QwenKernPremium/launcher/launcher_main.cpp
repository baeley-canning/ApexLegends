// ============================================================================
// apex_launcher.exe — QwenKern Premium launcher
//
// Responsibilities
//   * locate r5apex.exe (or accept an explicit PID)
//   * let the operator pick the injection strategy (usermode x2, kernel driver)
//   * expose the launcher-side evasion switches (staged DLL copy, randomised
//     method, delayed injection)
//   * perform the injection through ApexInjector and report the outcome
//
// The launcher NEVER touches game memory itself: all game-facing work happens
// in apexcheat.dll (usermode) or apexdrv.sys (kernel), which keeps the
// launcher's own footprint small.
// ============================================================================

#include "injector.h"
#include "acg_probe.h"

#include <windows.h>
#include <tlhelp32.h>

#include <cstdio>
#include <cstdlib>
#include <cctype>
#include <fstream>
#include <iostream>
#include <random>
#include <string>
#include <vector>

#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "psapi.lib")

namespace {

// The game's real process image after the 2026-09-29 EA Javelin move.  The
// legacy name is still accepted (and reported) because a stale install or a
// different store build must not be mistaken for "game not running".
const char* const kGameProcessName      = "r5apex_dx12.exe";
const char* const kLegacyProcessName    = "r5apex.exe";
const char* const kDefaultDllName  = "apexcheat.dll";
const char* const kDefaultDriver   = "apexdrv.sys";

// The reference install (C:\Program Files\EA Games\Apex) ALSO holds
// "baeleys game.exe": a byte-identical copy of r5apex_dx12.exe (same size and
// SHA-256, verified 2026-10-26), i.e. the game renamed by the player.  It is the
// game, but the matched name is recorded AND compared, so a module-base or
// import-table assumption can never silently ride on the wrong binary.
const char* const kCopiedProcessName    = "baeleys game.exe";

// Order = preference: the canonical name wins when several images are running.
const char* const kKnownProcessNames[]  = {
    kGameProcessName,
    kLegacyProcessName,
    kCopiedProcessName,
};

bool IsKnownGameImageName(const std::string& imageName) {
    for (const char* const name : kKnownProcessNames) {
        if (_stricmp(imageName.c_str(), name) == 0) return true;
    }
    return false;
}

struct LauncherOptions {
    std::string     dllPath;
    std::string     driverPath;
    InjectionMethod method           = InjectionMethod::NtCreateThreadEx;
    bool            methodForced     = false;  // --method=<x> given: no ladder
    bool            randomizeMethod  = false;
    bool            stageDll         = false;   // inject from a random-named copy
    bool            waitForGame      = true;
    DWORD           waitTimeoutMs    = 120000;
    DWORD           explicitPid      = 0;
    bool            runProbe         = false;   // --probe: measure, do not inject
    bool            runKernelProbe   = false;   // --kernel-probe: Q10, driver only
    bool            allowSticky      = true;    // persist/read the working rung
    bool            forgetSticky     = false;
};

void PrintBanner() {
    printf("===============================================================\n");
    printf("  QwenKern Premium - Apex Legends launcher\n");
    printf("  usermode ladder: A8/A7 manual | A4 hijack | A3 APC | A2 NtCTE | A1 CRT\n");
    printf("  kernel rung    : B3 (apexdrv.sys)\n");
    printf("===============================================================\n");
}

bool IsElevated() {
    BOOL elevated = FALSE;
    HANDLE token = nullptr;

    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
        TOKEN_ELEVATION elevation{};
        DWORD returned = 0;
        if (GetTokenInformation(token, TokenElevation, &elevation,
                                sizeof(elevation), &returned)) {
            elevated = elevation.TokenIsElevated;
        }
        CloseHandle(token);
    }
    return elevated != FALSE;
}

std::string ExeDirectory() {
    char modulePath[MAX_PATH] = { 0 };
    if (GetModuleFileNameA(nullptr, modulePath, MAX_PATH) == 0) return std::string();

    std::string path(modulePath);
    const size_t slash = path.find_last_of("\\/");
    return (slash == std::string::npos) ? std::string() : path.substr(0, slash + 1);
}

bool FileExists(const std::string& path) {
    const DWORD attributes = GetFileAttributesA(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES &&
           (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::wstring Widen(const std::string& text) {
    if (text.empty()) return std::wstring();
    const int needed = MultiByteToWideChar(CP_ACP, 0, text.c_str(), -1, nullptr, 0);
    if (needed <= 1) return std::wstring();

    std::wstring wide(static_cast<size_t>(needed), L'\0');
    MultiByteToWideChar(CP_ACP, 0, text.c_str(), -1, &wide[0], needed);
    wide.resize(static_cast<size_t>(needed - 1));
    return wide;
}

std::string Lowercase(std::string text) {
    for (size_t i = 0; i < text.size(); ++i) {
        text[i] = static_cast<char>(::tolower(static_cast<unsigned char>(text[i])));
    }
    return text;
}

DWORD FindProcessIdByName(const char* exeName) {
    DWORD pid = 0;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;

    PROCESSENTRY32 entry{};
    entry.dwSize = sizeof(entry);

    if (Process32First(snapshot, &entry)) {
        do {
            if (_stricmp(entry.szExeFile, exeName) == 0) {
                pid = entry.th32ProcessID;
                break;
            }
        } while (Process32Next(snapshot, &entry));
    }

    CloseHandle(snapshot);
    return pid;
}

// Which image name matched the last successful lookup (for logs + integrity).
const char* g_matchedProcessName = "";

// Post-Javelin the image is r5apex_dx12.exe.  Accept the legacy name too, but
// always record WHICH one matched: "the game was found" must be verifiable, and
// an unknown image name is exactly what breaks module-base assumptions later.
DWORD FindGameProcessId() {
    for (const char* const name : kKnownProcessNames) {
        const DWORD pid = FindProcessIdByName(name);
        if (pid != 0) {
            g_matchedProcessName = name;
            return pid;
        }
    }

    g_matchedProcessName = "";
    return 0;
}

std::string RandomToken(size_t length) {
    static const char alphabet[] = "abcdefghijklmnopqrstuvwxyz0123456789";

    std::random_device device;
    std::mt19937 generator(device());
    std::uniform_int_distribution<int> distribution(
        0, static_cast<int>(sizeof(alphabet) - 2));

    std::string token;
    token.reserve(length);
    for (size_t i = 0; i < length; ++i) {
        token.push_back(alphabet[distribution(generator)]);
    }
    return token;
}

// Copy the payload to %TEMP% under a random name.  Windows keeps a loaded
// image mapped after the file is deleted, so a path/name based heuristic sees
// nothing recognisable and no tell-tale file stays on disk.
bool StageDllCopy(const std::string& sourcePath, std::string& stagedPath) {
    char tempDirectory[MAX_PATH] = { 0 };
    if (GetTempPathA(MAX_PATH, tempDirectory) == 0) return false;

    stagedPath = std::string(tempDirectory) + RandomToken(10) + ".dll";
    if (!CopyFileA(sourcePath.c_str(), stagedPath.c_str(), FALSE)) {
        stagedPath.clear();
        return false;
    }
    return true;
}

InjectionMethod RandomizedMethod() {
    std::random_device device;
    std::mt19937 generator(device());
    std::uniform_int_distribution<int> distribution(0, 1);

    return distribution(generator) == 0 ? InjectionMethod::NtCreateThreadEx
                                        : InjectionMethod::ApcQueue;
}

void PrintResult(const InjectionResult& result, InjectionMethod method) {
    printf("---------------------------------------------------------------\n");
    if (result.success) {
        printf("[+] Injection succeeded via %s\n", InjectionMethodName(method));
        printf("    thread id  : %lu\n", result.threadId);
        printf("    module base: 0x%p\n",
               reinterpret_cast<void*>(result.dllBaseAddress));
    } else {
        printf("[-] Injection FAILED via %s\n", InjectionMethodName(method));
        if (!result.errorMessage.empty()) {
            printf("    reason: %s\n", result.errorMessage.c_str());
        }
    }
    printf("---------------------------------------------------------------\n");
}

// Resolve a payload next to the launcher, falling back to build\ and ..\build\.
std::string ResolvePayloadPath(const std::string& candidate) {
    if (!candidate.empty() && FileExists(candidate)) return candidate;

    const std::string exeDir = ExeDirectory();
    if (exeDir.empty()) return candidate;

    const std::string local = exeDir + candidate;
    if (FileExists(local)) return local;

    const std::string build = exeDir + "build\\" + candidate;
    if (FileExists(build)) return build;

    return candidate;
}

// Wait for the game process to appear (launcher started before the game).
DWORD WaitForGameProcess(DWORD timeoutMs) {
    const DWORD start = GetTickCount();
    DWORD pid = FindGameProcessId();   // any known image name, not just canonical

    while (pid == 0) {
        if (GetTickCount() - start > timeoutMs) return 0;

        printf(".");           // progress dot every second
        fflush(stdout);
        Sleep(1000);
        pid = FindGameProcessId();
    }

    if (GetTickCount() - start > 0) printf("\n");
    return pid;
}

DWORD PromptPid() {
    printf("Enter target PID (0 = cancel): ");
    fflush(stdout);

    char buffer[32] = { 0 };
    if (!fgets(buffer, sizeof(buffer), stdin)) return 0;

    return static_cast<DWORD>(strtoul(buffer, nullptr, 10));
}

const char* MethodLabel(InjectionMethod method) {
    switch (method) {
        case InjectionMethod::NtCreateThreadEx: return "NtCreateThreadEx (HIDE)";
        case InjectionMethod::ApcQueue:         return "APC Queue (IMPERSONATE)";
        case InjectionMethod::KernelDriver:     return "Kernel Driver (KERNEL)";
        case InjectionMethod::CreateRemoteThread: return "CreateRemoteThread (A1)";
        case InjectionMethod::ManualMap:        return "Manual Map (MANUAL)";
        case InjectionMethod::ThreadHijack:     return "Thread Hijack (HIJACK)";
        case InjectionMethod::VadLessMap:       return "VAD-less Map (GHOST)";
        default:                                return "?";
    }
}

// ============================================================================
// PHASE 1.2 — sticky strategy choice
//
// The working rung is remembered PER MACHINE (next to the launcher, so per
// install rather than per user profile) and tried FIRST next run.  Every
// attempt is still logged, so a machine that silently changes its mind stays
// visible instead of invisible.
// ============================================================================
std::string StickyFilePath() {
    return ExeDirectory() + "apexcheat.launcher.ini";
}

std::string TrimText(const std::string& text) {
    size_t begin = 0;
    size_t end   = text.size();
    while (begin < end && std::isspace(static_cast<unsigned char>(text[begin]))) ++begin;
    while (end > begin && std::isspace(static_cast<unsigned char>(text[end - 1]))) --end;
    return text.substr(begin, end - begin);
}

bool ParseMethodCode(const std::string& code, InjectionMethod& methodOut) {
    const std::string normalized = Lowercase(TrimText(code));

    static const InjectionMethod methods[] = {
        InjectionMethod::NtCreateThreadEx,
        InjectionMethod::ApcQueue,
        InjectionMethod::CreateRemoteThread,
        InjectionMethod::KernelDriver,
        InjectionMethod::ManualMap,
        InjectionMethod::ThreadHijack,
        InjectionMethod::VadLessMap,
    };

    for (size_t i = 0; i < sizeof(methods) / sizeof(methods[0]); ++i) {
        if (normalized == Lowercase(InjectionMethodCode(methods[i]))) {
            methodOut = methods[i];
            return true;
        }
    }
    return false;
}

bool ReadStickyMethod(InjectionMethod& methodOut, std::string& payloadOut) {
    std::ifstream file(StickyFilePath().c_str());
    if (!file.is_open()) return false;

    bool found = false;
    std::string line;
    while (std::getline(file, line)) {
        const size_t equals = line.find('=');
        if (equals == std::string::npos) continue;

        const std::string key   = Lowercase(TrimText(line.substr(0, equals)));
        const std::string value = TrimText(line.substr(equals + 1));

        if (key == "strategy" && ParseMethodCode(value, methodOut)) found = true;
        else if (key == "payload") payloadOut = value;
    }
    return found;
}

bool WriteStickyMethod(InjectionMethod method, const std::string& payload) {
    std::ofstream file(StickyFilePath().c_str(), std::ios::trunc);
    if (!file.is_open()) return false;

    SYSTEMTIME now{};
    GetLocalTime(&now);

    char stamp[32] = { 0 };
    sprintf_s(stamp, sizeof(stamp), "%04u-%02u-%02u %02u:%02u:%02u",
              static_cast<unsigned>(now.wYear),   static_cast<unsigned>(now.wMonth),
              static_cast<unsigned>(now.wDay),    static_cast<unsigned>(now.wHour),
              static_cast<unsigned>(now.wMinute), static_cast<unsigned>(now.wSecond));

    file << "# QwenKern launcher - last strategy that VERIFIED on this machine.\n";
    file << "# Written by the ladder in PHASE 1.2; delete the file to forget it.\n";
    file << "strategy=" << InjectionMethodCode(method) << "\n";
    file << "payload=" << payload << "\n";
    file << "verified=" << stamp << "\n";
    return true;
}

void ForgetStickyMethod() {
    const std::string path = StickyFilePath();
    if (DeleteFileA(path.c_str())) {
        printf("[*] Sticky strategy forgotten (%s)\n", path.c_str());
    } else {
        printf("[*] Nothing to forget (%s)\n", path.c_str());
    }
}

// ============================================================================
// PHASE 1.3 — reference integrity
//
// Three independent facts must hold before an injection result means anything:
//   1. the target image is the expected process (not our own launcher),
//   2. the module base is a real PE image we can read,
//   3. the render backend is ALREADY mapped by the game - we must not be the
//      reason d3d11/dxgi appears in the target (that would be a fingerprint).
// A failure is reported, not fatal: the roadmap wants the facts recorded.
// ============================================================================
struct ReferenceIntegrity {
    bool        imageNameMatches;
    bool        baseIsPe;
    bool        d3d11Loaded;
    bool        dxgiLoaded;
    bool        d3d12Loaded;
    bool        d3d9Loaded;
    int         moduleCount;
    ULONGLONG   moduleBase;
    std::string imageName;
};

ULONGLONG QueryMainModuleBase(DWORD pid, std::string& imageNameOut, int& moduleCountOut) {
    moduleCountOut = 0;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;

    MODULEENTRY32 entry{};
    entry.dwSize = sizeof(entry);

    ULONGLONG base = 0;
    if (Module32First(snapshot, &entry)) {
        base = reinterpret_cast<ULONGLONG>(entry.modBaseAddr);
        imageNameOut = entry.szModule;
        do { ++moduleCountOut; } while (Module32Next(snapshot, &entry));
    }

    CloseHandle(snapshot);
    return base;
}

ReferenceIntegrity CollectReferenceIntegrity(DWORD pid) {
    ReferenceIntegrity facts{};
    facts.moduleBase  = QueryMainModuleBase(pid, facts.imageName, facts.moduleCount);
    facts.d3d11Loaded = ApexInjector::IsModuleLoaded(pid, "d3d11.dll");
    facts.dxgiLoaded  = ApexInjector::IsModuleLoaded(pid, "dxgi.dll");
    facts.d3d12Loaded = ApexInjector::IsModuleLoaded(pid, "d3d12.dll");
    facts.d3d9Loaded  = ApexInjector::IsModuleLoaded(pid, "d3d9.dll");

    facts.imageNameMatches = IsKnownGameImageName(facts.imageName);
    facts.baseIsPe = false;

    HANDLE process = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, FALSE, pid);
    if (process && facts.moduleBase != 0) {
        IMAGE_DOS_HEADER dos{};
        SIZE_T read = 0;
        if (ReadProcessMemory(process, reinterpret_cast<LPCVOID>(facts.moduleBase),
                              &dos, sizeof(dos), &read) && dos.e_magic == IMAGE_DOS_SIGNATURE) {
            IMAGE_NT_HEADERS64 nt{};
            const void* ntAddress = reinterpret_cast<const void*>(
                facts.moduleBase + static_cast<ULONGLONG>(dos.e_lfanew));
            if (ReadProcessMemory(process, ntAddress, &nt, sizeof(nt), &read) &&
                nt.Signature == IMAGE_NT_SIGNATURE) {
                facts.baseIsPe = true;
            }
        }
    }
    if (process) CloseHandle(process);

    return facts;
}

void PrintReferenceIntegrity(const ReferenceIntegrity& facts) {
    printf("[*] reference integrity:\n");
    printf("    image            : %s %s\n", facts.imageName.c_str(),
           facts.imageNameMatches ? "(expected, post-Javelin name)"
                                  : "(NOT the expected r5apex_dx12.exe)");
    printf("    module base      : 0x%llX %s\n",
           static_cast<unsigned long long>(facts.moduleBase),
           facts.baseIsPe ? "(PE headers readable)" : "(NOT a readable PE image)");
    printf("    modules in target: %d\n", facts.moduleCount);

    // Under the live Javelin blackout the module list itself is unreadable, so a
    // flat "absent" would be a lie: with 0 modules read the truth is UNKNOWN.
    const bool blind = (facts.moduleCount == 0);
    const char* const noText = blind ? "unknown" : "absent";
    printf("    render modules   : d3d11=%s dxgi=%s d3d12=%s d3d9=%s\n",
           facts.d3d11Loaded ? "loaded" : noText,
           facts.dxgiLoaded  ? "loaded" : noText,
           facts.d3d12Loaded ? "loaded" : noText,
           facts.d3d9Loaded  ? "loaded" : noText);

    if (!blind && !facts.d3d11Loaded && facts.d3d12Loaded) {
        printf("    [!] DX12 is up and d3d11 is NOT mapped: our d3d11.dll import would\n"
               "        ADD a module the game never loaded (see LOCAL GROUND TRUTH in\n"
               "        PHASE1_LADDER_AND_LIVE_ACCESS_MEASUREMENT.txt)\n");
    }
    if (!blind && facts.d3d9Loaded) {
        printf("    [i] d3d9.dll is present: the D3D9 fallback hook is reachable\n");
    }
    if (blind) {
        printf("    [!] module snapshot EMPTY (OpenProcess/TH32CS_SNAPMODULE denied):\n"
               "        every 'unknown' above is genuinely UNMEASURED, not absent ->\n"
               "        run the launcher ELEVATED, otherwise every verdict below is\n"
               "        meaningless\n");
    }
}

// Can the target's module list be read at all?  Apex under Javelin is a live
// example of "no": without this check a rung whose payload loaded fine would be
// reported FAIL simply because the snapshot failed.
bool ModuleListReadable(DWORD pid) {
    std::string imageName;
    int count = 0;
    return QueryMainModuleBase(pid, imageName, count) != 0 && count > 0;
}

InjectionResult RunInjection(const LauncherOptions& options, DWORD pid) {
    ApexInjector injector;

    InjectionMethod method = options.method;
    if (options.randomizeMethod && method != InjectionMethod::KernelDriver) {
        method = RandomizedMethod();
        printf("[*] Randomised usermode method -> %s\n", InjectionMethodName(method));
    }

    std::string payload = options.dllPath;
    std::string stagedPath;

    if (options.stageDll) {
        if (StageDllCopy(options.dllPath, stagedPath)) {
            payload = stagedPath;
            printf("[*] Staged payload copy: %s\n", stagedPath.c_str());
        } else {
            printf("[!] Staging failed (0x%08lX), injecting original path\n",
                   GetLastError());
        }
    }

    printf("[*] Target PID %lu, payload %s\n", pid, payload.c_str());
    InjectionResult result = injector.Inject(pid, payload, method, options.driverPath);

    // Safe to delete: the loader keeps the mapped image alive.
    if (!stagedPath.empty()) {
        if (DeleteFileA(stagedPath.c_str())) {
            printf("[*] Staged copy removed from disk\n");
        }
    }

    PrintResult(result, method);
    return result;
}

// Basename of a path, used as the module-list key for the ladder verdict.
std::string BaseNameOfPath(const std::string& path) {
    const size_t slash = path.find_last_of("\\/");
    return (slash == std::string::npos) ? path : path.substr(slash + 1);
}

// ============================================================================
// PHASE 1.2 — the strategy ladder
//
// Least-invasive-first, and it is a LADDER not a menu: every rung goes through
// the same verdict so "success" means the payload is actually mapped:
//   1. the injector call returns success,
//   2. the payload appears in the target's module list.
// A rung that passes 1 and fails 2 is a FAIL with the reason spelled out — that
// is the AGC pattern from docs\JAVELIN_2026_*: the call "works", the image
// never initialises.
// ============================================================================
std::vector<InjectionMethod> BuildLadderOrder(const LauncherOptions& options,
                                              bool haveSticky, InjectionMethod sticky) {
    std::vector<InjectionMethod> order;

    // Sticky rung first: state on disk exists to short-circuit a ladder that
    // already found its answer on this machine.
    if (haveSticky) order.push_back(sticky);

    // Roadmap order (PHASE 1.2 / INJECTION_MENU_AND_RISK_MATRIX): the rungs are
    // tried strongest-first among the ones that leave the least loader trace:
    //   A7 manual map  -> no loader, no PEB entry
    //   A4 hijack      -> no new thread, no APC
    //   A3 APC         -> no new thread
    //   A2 NtCTE       -> new thread via ntdll
    //   A1 CRT         -> new thread via kernel32
    // A8 (VAD-less) is declared but not implemented, so it is listed here and
    // SKIPped by the ladder: the log then shows the whole ladder instead of
    // silently omitting a rung.
    const InjectionMethod leaves[] = {
        InjectionMethod::VadLessMap,
        InjectionMethod::ManualMap,
        InjectionMethod::ThreadHijack,
        InjectionMethod::ApcQueue,
        InjectionMethod::NtCreateThreadEx,
        InjectionMethod::CreateRemoteThread,
    };

    for (size_t i = 0; i < sizeof(leaves) / sizeof(leaves[0]); ++i) {
        if (haveSticky && leaves[i] == sticky) continue;
        order.push_back(leaves[i]);
    }

    // Kernel rung last.  Appended even when the driver cannot run, so the run
    // log shows the rung and its SKIP reason instead of silently omitting it.
    if ((!haveSticky || sticky != InjectionMethod::KernelDriver)) {
        order.push_back(InjectionMethod::KernelDriver);
    }

    // A B3 rung without a staged driver (or without elevation) is a guaranteed
    // SKIP - surface that in the plan, before the first rung runs.
    if (!FileExists(options.driverPath)) {
        printf("[i] B3 (kernel) will SKIP: driver not staged (%s)\n",
               options.driverPath.c_str());
    } else if (!IsElevated()) {
        printf("[i] B3 (kernel) will SKIP: launcher is not elevated\n");
    }

    return order;
}

struct LadderOutcome {
    bool            verified;
    InjectionMethod method;
    InjectionResult last;
};

// How long a rung may keep loading the payload before it is called a failure.
// Needed because an APC rung (A3) is delivered on the target's NEXT alertable
// wait: checking the module list the instant the injector returns would reject a
// strategy that works, i.e. it would corrupt the measurement.
const DWORD kVerifyWindowMs = 3000;

bool WaitForModule(DWORD pid, const char* moduleName, DWORD timeoutMs) {
    const DWORD start = GetTickCount();
    for (;;) {
        if (ApexInjector::IsModuleLoaded(pid, moduleName)) return true;
        if (GetTickCount() - start >= timeoutMs) return false;
        Sleep(50);
    }
}

// A manual-mapped payload is deliberately absent from the module list, so its
// verdict is "a readable PE header at the base we mapped it to" plus the entry
// point having returned TRUE (result.entryExecuted).  Weaker than a module-list
// hit on purpose: it proves the image and the call, not loader bookkeeping.
bool ImageReadable(DWORD pid, ULONGLONG base) {
    if (base == 0) return false;

    HANDLE process = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, FALSE, pid);
    if (!process) return false;

    IMAGE_DOS_HEADER dos{};
    SIZE_T read = 0;
    const bool ok = ReadProcessMemory(process, reinterpret_cast<LPCVOID>(base), &dos,
                                      sizeof(dos), &read) != FALSE &&
                    dos.e_magic == IMAGE_DOS_SIGNATURE;

    CloseHandle(process);
    return ok;
}

bool WaitForMappedImage(DWORD pid, ULONGLONG base, DWORD timeoutMs) {
    const DWORD start = GetTickCount();
    for (;;) {
        if (ImageReadable(pid, base)) return true;
        if (GetTickCount() - start >= timeoutMs) return false;
        Sleep(50);
    }
}

InjectionResult RunLadder(const LauncherOptions& options, DWORD pid, LadderOutcome& outcome) {
    outcome.verified = false;
    outcome.method   = options.method;
    outcome.last     = InjectionResult{};

    InjectionMethod sticky = InjectionMethod::NtCreateThreadEx;
    std::string     stickyPayload;
    const bool haveSticky = options.allowSticky && ReadStickyMethod(sticky, stickyPayload);

    if (haveSticky) {
        printf("[*] Sticky rung: %s (last verified payload '%s')\n",
               InjectionMethodName(sticky), stickyPayload.c_str());
    } else {
        printf("[*] No sticky rung on this machine; ladder starts at the top\n");
    }

    std::string payload = options.dllPath;
    std::string stagedPath;
    if (options.stageDll) {
        if (StageDllCopy(options.dllPath, stagedPath)) payload = stagedPath;
    }
    const std::string moduleName = BaseNameOfPath(payload);

    const std::vector<InjectionMethod> order = BuildLadderOrder(options, haveSticky, sticky);
    printf("[*] %d rung(s), target PID %lu, payload %s\n",
           static_cast<int>(order.size()), pid, moduleName.c_str());
    printf("    verdict rule: A1-A4 count when %s is in the target's module list;\n"
           "                  A7/A8 count on a readable image + a completed entry call\n",
           moduleName.c_str());

    // Probe the measuring instrument before trusting any verdict: Apex runs at a
    // higher integrity level than a plain launcher, and a denied snapshot turns
    // every rung into a false FAIL.
    if (!ModuleListReadable(pid)) {
        printf("[!] module list of PID %lu is NOT readable -> verdicts are unreliable\n"
               "    relaunch the launcher elevated (Run as administrator) and retry\n", pid);
    }

    ApexInjector injector;

    for (size_t i = 0; i < order.size(); ++i) {
        const InjectionMethod method = order[i];
        const int step  = static_cast<int>(i) + 1;
        const int total = static_cast<int>(order.size());

        printf("[%d/%d] %s\n", step, total, InjectionMethodName(method));

        if (!InjectionMethodImplemented(method)) {
            printf("       SKIP : not implemented in this build\n");
            continue;
        }
        if (method == InjectionMethod::KernelDriver) {
            if (!FileExists(options.driverPath)) {
                printf("       SKIP : driver not staged (%s)\n", options.driverPath.c_str());
                continue;
            }
            if (!IsElevated()) {
                printf("       SKIP : driver rung needs elevation\n");
                continue;
            }
        }

        const InjectionResult result = injector.Inject(pid, payload, method, options.driverPath);
        outcome.last   = result;
        outcome.method = method;

        if (!result.success) {
            printf("       FAIL : %s\n", result.errorMessage.empty()
                                            ? "injector reported failure"
                                            : result.errorMessage.c_str());
            continue;
        }

        // A7/A8 verdict: the payload is deliberately NOT in the module list.
        if (!result.moduleListVerdict) {
            const ULONGLONG base = reinterpret_cast<ULONGLONG>(result.dllBaseAddress);
            if (!WaitForMappedImage(pid, base, kVerifyWindowMs)) {
                printf("       FAIL : call succeeded but no readable PE image at 0x%llX (%lu ms window)\n",
                       static_cast<unsigned long long>(base), kVerifyWindowMs);
                continue;
            }
            if (!result.entryExecuted) {
                printf("       FAIL : image mapped at 0x%llX but the entry point never returned TRUE\n",
                       static_cast<unsigned long long>(base));
                continue;
            }
            printf("       PASS : image at 0x%llX, entry executed (absent from the module list by design)\n",
                   static_cast<unsigned long long>(base));
            outcome.verified = true;

            if (options.allowSticky && WriteStickyMethod(method, moduleName)) {
                printf("       sticky: %s remembered (%s)\n",
                       InjectionMethodCode(method), StickyFilePath().c_str());
            }
            if (!stagedPath.empty()) DeleteFileA(stagedPath.c_str());
            return result;
        }

        const DWORD verifyStart = GetTickCount();
        if (!WaitForModule(pid, moduleName.c_str(), kVerifyWindowMs)) {
            printf("       FAIL : call succeeded but %s never appeared in the target (%lu ms window)\n",
                   moduleName.c_str(), kVerifyWindowMs);
            continue;
        }

        printf("       PASS : %s present at 0x%p (thread %lu, visible after %lu ms)\n",
               moduleName.c_str(), reinterpret_cast<void*>(result.dllBaseAddress),
               result.threadId, GetTickCount() - verifyStart);
        outcome.verified = true;

        if (options.allowSticky && WriteStickyMethod(method, moduleName)) {
            printf("       sticky: %s remembered (%s)\n",
                   InjectionMethodCode(method), StickyFilePath().c_str());
        }
        if (!stagedPath.empty()) DeleteFileA(stagedPath.c_str());
        return result;
    }

    if (!stagedPath.empty()) DeleteFileA(stagedPath.c_str());
    printf("[-] Ladder exhausted: no rung verified the payload\n");
    return outcome.last;
}

// PHASE 1.1 in launcher form: measure, never inject.  Falls back to our own PID
// so it is runnable with the game closed (results are only comparable within
// the same process kind, hence the explicit self/target tag on the report).
int RunProbeCommand(DWORD pid) {
    const DWORD targetPid = (pid != 0) ? pid : GetCurrentProcessId();
    const bool  self      = (targetPid == GetCurrentProcessId());
    const char* tag       = self ? "self" : "target";

    printf("[*] AG measurement harness (%s PID %lu)%s\n", tag, targetPid,
           self ? " - game not running, measuring the launcher itself" : "");

    const ProbeEnvironment env = self ? AcgProbe::DescribeSelf()
                                      : AcgProbe::DescribeProcess(targetPid);
    printf("%s", AcgProbe::FormatEnvironment(env).c_str());

    // PHASE 1.3: reference facts for the same target, taken BEFORE any payload
    // is introduced, so "d3d11 is loaded" cannot be our own doing.
    if (!self) PrintReferenceIntegrity(CollectReferenceIntegrity(targetPid));

    const std::vector<ProbeResult> results =
        self ? AcgProbe::RunInternal() : AcgProbe::RunExternal(targetPid);
    printf("%s", AcgProbe::FormatReport("ACG measurement", env, results).c_str());

    int passed = 0;
    for (size_t i = 0; i < results.size(); ++i) {
        if (results[i].passed) ++passed;
    }

    // Advisory only - the ladder never reads this string.
    printf("[*] recommendation: %s\n", AcgProbe::Recommendation(results).c_str());
    printf("[*] measured %d/%d probe(s) passing\n", passed,
           static_cast<int>(results.size()));

    const std::string reportPath = AcgProbe::DefaultReportPath(tag);
    std::string error;
    if (AcgProbe::WriteReportFile(reportPath, "ACG measurement", env, results, error)) {
        printf("[*] report written: %s\n", reportPath.c_str());
    } else {
        printf("[!] report NOT written: %s\n", error.c_str());
    }

    return (passed == static_cast<int>(results.size())) ? 0 : 4;
}

// PHASE 1.4 / Q10: ask the driver what KERNEL context can do, without injecting.
// Elevated only (SCM).  Exit codes: 0 = driver answered (read the table),
// 3 = driver/service problem, 5 = no target.
int RunKernelProbe(const LauncherOptions& options) {
    printf("[*] Kernel reachability probe - the driver is loaded for this call and\n"
           "    removed again afterwards; nothing is injected\n");
    printf("[*] driver: %s\n", options.driverPath.c_str());

    if (!FileExists(options.driverPath)) {
        printf("[-] driver not staged: %s\n", options.driverPath.c_str());
        return 3;
    }

    DWORD pid = options.explicitPid;
    if (pid == 0) {
        pid = options.waitForGame ? WaitForGameProcess(options.waitTimeoutMs)
                                  : FindGameProcessId();
    }
    if (pid == 0) {
        printf("[-] no target PID (pass --pid=<pid>)\n");
        return 5;
    }
    printf("[*] target: %s PID %lu\n",
           (*g_matchedProcessName != '\0') ? g_matchedProcessName : "(explicit pid)",
           pid);

    ApexInjector injector;
    std::string report;
    const bool answered = injector.ProbeViaKernel(pid, options.driverPath, report);
    printf("%s", report.c_str());

    const std::string exeDir = ExeDirectory();
    const std::string reportPath =
        exeDir + ((!exeDir.empty() && (exeDir.back() == '\\' || exeDir.back() == '/'))
                      ? "" : "\\") + "apexdrv_probe.txt";
    FILE* file = nullptr;
    if (fopen_s(&file, reportPath.c_str(), "wb") == 0 && file != nullptr) {
        fwrite(report.c_str(), 1, report.size(), file);
        fclose(file);
        printf("[*] report written: %s\n", reportPath.c_str());
    } else {
        printf("[!] report NOT written: %s\n", reportPath.c_str());
    }

    return answered ? 0 : 3;
}

void PrintMenu(const LauncherOptions& options, DWORD pid) {
    printf("\n--- configuration ---------------------------------------------\n");
    printf("  1) method            : %s%s\n", MethodLabel(options.method),
           options.randomizeMethod ? "  [randomised]" : "");
    printf("  2) payload DLL       : %s\n", options.dllPath.c_str());
    printf("  3) kernel driver     : %s\n", options.driverPath.c_str());
    printf("  4) staged DLL copy   : %s\n", options.stageDll ? "on" : "off");
    printf("  5) wait for game     : %s (%lu s)\n",
           options.waitForGame ? "on" : "off", options.waitTimeoutMs / 1000);
    printf("  6) sticky strategy   : %s\n", options.allowSticky ? "on" : "off");
    if (pid) printf("     game PID          : %lu\n", pid);
    else     printf("     game PID          : not running\n");
    printf("----------------------------------------------------------------\n");
    printf("  [i] inject (ladder)   [1] cycle method   [2] set DLL path\n");
    printf("  [3] set driver path   [4] toggle staging   [5] toggle wait\n");
    printf("  [6] toggle sticky     [p] enter PID   [q] quit\n");
    printf("> ");
    fflush(stdout);
}

// Returns true when the launcher should keep running.
bool InteractiveMenu(LauncherOptions& options, bool gameFound) {
    DWORD pid = gameFound ? FindGameProcessId() : 0;

    for (;;) {
        PrintMenu(options, pid);

        char line[64] = { 0 };
        if (!fgets(line, sizeof(line), stdin)) return false;

        const char choice = Lowercase(std::string(line, 1))[0];

        if (choice == 'q' || choice == '\n') return false;

        if (choice == '1') {
            // Same order the ladder uses, so cycling the menu never hides a rung.
            static const InjectionMethod cycle[] = {
                InjectionMethod::ManualMap,
                InjectionMethod::ThreadHijack,
                InjectionMethod::ApcQueue,
                InjectionMethod::NtCreateThreadEx,
                InjectionMethod::CreateRemoteThread,
                InjectionMethod::KernelDriver,
            };
            const size_t count = sizeof(cycle) / sizeof(cycle[0]);

            size_t next = 0;
            for (size_t i = 0; i < count; ++i) {
                if (cycle[i] == options.method) {
                    next = (i + 1) % count;
                    break;
                }
            }
            options.method = cycle[next];
            printf("[*] Method set to %s\n", MethodLabel(options.method));
            continue;
        }

        if (choice == '2') {
            printf("DLL path [%s]: ", options.dllPath.c_str());
            fflush(stdout);
            if (fgets(line, sizeof(line), stdin)) {
                std::string entered(line);
                while (!entered.empty() &&
                       (entered.back() == '\n' || entered.back() == '\r')) {
                    entered.pop_back();
                }
                if (!entered.empty()) options.dllPath = ResolvePayloadPath(entered);
            }
            continue;
        }

        if (choice == '3') {
            printf("Driver path [%s]: ", options.driverPath.c_str());
            fflush(stdout);
            if (fgets(line, sizeof(line), stdin)) {
                std::string entered(line);
                while (!entered.empty() &&
                       (entered.back() == '\n' || entered.back() == '\r')) {
                    entered.pop_back();
                }
                if (!entered.empty()) options.driverPath = ResolvePayloadPath(entered);
            }
            continue;
        }

        if (choice == '4') {
            options.stageDll = !options.stageDll;
            printf("[*] Staged DLL copy %s\n", options.stageDll ? "enabled" : "disabled");
            continue;
        }

        if (choice == '5') {
            options.waitForGame = !options.waitForGame;
            printf("[*] Wait-for-game %s\n", options.waitForGame ? "enabled" : "disabled");
            continue;
        }

        if (choice == '6') {
            options.allowSticky = !options.allowSticky;
            printf("[*] Sticky strategy %s\n", options.allowSticky ? "enabled" : "disabled");
            if (!options.allowSticky) ForgetStickyMethod();
            continue;
        }

        if (choice == 'p') {
            const DWORD enteredPid = PromptPid();
            if (enteredPid != 0) pid = enteredPid;
            continue;
        }

        if (choice == 'i') {
            if (pid == 0) {
                pid = options.waitForGame
                        ? WaitForGameProcess(options.waitTimeoutMs)
                        : FindGameProcessId();
            }
            if (pid == 0) {
                printf("[-] r5apex.exe not found\n");
                continue;
            }

            if (!FileExists(options.dllPath)) {
                printf("[-] Payload missing: %s\n", options.dllPath.c_str());
                continue;
            }
            if (options.method == InjectionMethod::KernelDriver &&
                !FileExists(options.driverPath)) {
                printf("[-] Driver missing: %s\n", options.driverPath.c_str());
                continue;
            }

            // Forced rung = single honest measurement; otherwise the ladder
            // runs and the first VERIFIED rung becomes the machine's sticky.
            if (options.methodForced) {
                RunInjection(options, pid);
            } else {
                LadderOutcome outcome;
                RunLadder(options, pid, outcome);
                if (outcome.verified) {
                    printf("[*] Ladder settled on %s (%s)\n",
                           InjectionMethodName(outcome.method),
                           InjectionMethodCode(outcome.method));
                } else {
                    printf("[*] No rung verified. Use [1] or --method= to force one.\n");
                }
            }
            continue;
        }

        printf("[!] Unknown choice\n");
    }
}

enum class ArgResult { Continue, ExitSuccess, ExitError };

bool ParseMethod(const std::string& value, InjectionMethod& method) {
    const std::string normalized = Lowercase(value);

    if (normalized == "nt" || normalized == "ntcreatethreadex" || normalized == "hide") {
        method = InjectionMethod::NtCreateThreadEx;
        return true;
    }
    if (normalized == "apc" || normalized == "impersonate") {
        method = InjectionMethod::ApcQueue;
        return true;
    }
    if (normalized == "kernel" || normalized == "drv" || normalized == "driver") {
        method = InjectionMethod::KernelDriver;
        return true;
    }
    if (normalized == "crt" || normalized == "createremotethread" || normalized == "baseline") {
        method = InjectionMethod::CreateRemoteThread;
        return true;
    }
    if (normalized == "manual" || normalized == "manualmap" || normalized == "mm" ||
        normalized == "a7") {
        method = InjectionMethod::ManualMap;
        return true;
    }
    if (normalized == "hijack" || normalized == "threadhijack" || normalized == "a4") {
        method = InjectionMethod::ThreadHijack;
        return true;
    }
    if (normalized == "vadless" || normalized == "vad" || normalized == "a8") {
        method = InjectionMethod::VadLessMap;
        return true;
    }
    return false;
}

void PrintUsage() {
    printf("usage: apex_launcher.exe [options]\n\n");
    printf("  --inject                 run the LADDER once and exit (default)\n");
    printf("  --method=nt|apc|crt|hijack|manual|kernel  force ONE rung (no ladder, no sticky)\n");
    printf("  --probe                  AG measurement harness only, never injects\n");
    printf("  --kernel-probe           ask the driver what KERNEL context can do (Q10)\n");
    printf("  --dll=<path>             payload DLL (default: %s next to the exe)\n",
           kDefaultDllName);
    printf("  --driver=<path>          kernel driver for the B3 rung\n");
    printf("  --pid=<pid>              target PID (otherwise auto-detected)\n");
    printf("  --stage                  inject from a randomly named %%TEMP%% copy\n");
    printf("  --random                 randomise the usermode method per run\n");
    printf("  --timeout=<seconds>      wait-for-game timeout (default 120)\n");
    printf("  --no-wait                fail immediately if the game is not running\n");
    printf("  --no-sticky              do not read/write the per-machine rung\n");
    printf("  --forget-sticky          delete the remembered rung and continue\n");
    printf("  --help                   show this help\n\n");
    printf("Without any of the above the launcher opens its interactive menu.\n");
    printf("Ladder order: sticky rung, A8 (SKIP), A7, A4, A3, A2, A1, B3.  A rung\n");
    printf("counts when the payload is in the target's module list - except A7/A8,\n");
    printf("where the mapped image + a completed entry-point call is the verdict.\n");
}

ArgResult ParseArgs(int argc, char** argv, LauncherOptions& options, bool& runOnce) {
    runOnce = false;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        std::string value;

        const size_t equals = arg.find('=');
        if (equals != std::string::npos) {
            value = arg.substr(equals + 1);
            arg   = arg.substr(0, equals);
        }

        // Helper: value from "--opt=value" or from the next argv element.
        const auto takeValue = [&](std::string& out) -> bool {
            if (!value.empty()) { out = value; return true; }
            if (i + 1 < argc)   { out = argv[++i]; return true; }
            return false;
        };

        if (arg == "--help" || arg == "-h") {
            PrintUsage();
            return ArgResult::ExitSuccess;
        }
        if (arg == "--stage")   { options.stageDll = true;        continue; }
        if (arg == "--random")  { options.randomizeMethod = true; continue; }
        if (arg == "--no-wait") { options.waitForGame = false;    continue; }
        if (arg == "--inject") { runOnce = true;                  continue; }
        if (arg == "--probe")  { runOnce = true; options.runProbe = true; continue; }
        if (arg == "--kernel-probe") { runOnce = true; options.runKernelProbe = true; continue; }
        if (arg == "--no-sticky")     { options.allowSticky = false; continue; }
        if (arg == "--forget-sticky") { options.forgetSticky = true; continue; }

        if (arg == "--method") {
            std::string methodName;
            if (!takeValue(methodName) || !ParseMethod(methodName, options.method)) {
                printf("[-] Bad --method value\n");
                return ArgResult::ExitError;
            }
            // Forced: run exactly this rung, no ladder, no sticky.  A forced
            // method is a one-shot by definition, so it implies --inject;
            // without this the documented "--method=kernel" opened the menu.
            options.methodForced = true;
            runOnce = true;
            continue;
        }
        if (arg == "--dll") {
            std::string path;
            if (!takeValue(path)) { printf("[-] --dll needs a path\n"); return ArgResult::ExitError; }
            options.dllPath = ResolvePayloadPath(path);
            continue;
        }
        if (arg == "--driver") {
            std::string path;
            if (!takeValue(path)) { printf("[-] --driver needs a path\n"); return ArgResult::ExitError; }
            options.driverPath = ResolvePayloadPath(path);
            continue;
        }
        if (arg == "--pid") {
            std::string pidText;
            if (!takeValue(pidText)) { printf("[-] --pid needs a value\n"); return ArgResult::ExitError; }
            options.explicitPid = static_cast<DWORD>(strtoul(pidText.c_str(), nullptr, 10));
            continue;
        }
        if (arg == "--timeout") {
            std::string secondsText;
            if (!takeValue(secondsText)) { printf("[-] --timeout needs a value\n"); return ArgResult::ExitError; }
            options.waitTimeoutMs = static_cast<DWORD>(strtoul(secondsText.c_str(), nullptr, 10)) * 1000u;
            continue;
        }

        printf("[-] Unknown option: %s (try --help)\n", arg.c_str());
        return ArgResult::ExitError;
    }

    return ArgResult::Continue;
}

} // namespace

int main(int argc, char** argv) {
    LauncherOptions options;
    options.dllPath    = ResolvePayloadPath(kDefaultDllName);
    options.driverPath = ResolvePayloadPath(kDefaultDriver);

    bool runOnce = false;
    const ArgResult parsed = ParseArgs(argc, argv, options, runOnce);
    if (parsed == ArgResult::ExitSuccess) return 0;
    if (parsed == ArgResult::ExitError)   return 1;

    PrintBanner();

    // --forget-sticky applies to every path (probe included) and runs before
    // anything can read the file back.
    if (options.forgetSticky) ForgetStickyMethod();

    if (!IsElevated()) {
        printf("[!] Launcher is not elevated: opening r5apex.exe and loading a\n"
               "    kernel driver will likely fail.\n");
    }
    if (!FileExists(options.dllPath)) {
        printf("[!] Payload not found: %s\n", options.dllPath.c_str());
    }

    if (runOnce) {
        // --kernel-probe answers Q10 (can kernel context do what user mode
        // cannot?) without touching the target beyond reading its PEB.
        if (options.runKernelProbe) {
            return RunKernelProbe(options);
        }

        // --probe never injects: it resolves the same target, but a missing
        // game is not an error (the harness falls back to our own PID).
        if (options.runProbe) {
            const DWORD probePid = (options.explicitPid != 0)
                                       ? options.explicitPid
                                       : FindGameProcessId();
            return RunProbeCommand(probePid);
        }

        DWORD pid = options.explicitPid;
        if (pid == 0) {
            pid = options.waitForGame ? WaitForGameProcess(options.waitTimeoutMs)
                                      : FindGameProcessId();
        }
        if (pid == 0) {
            printf("[-] game image not found (looked for:");
            for (const char* const name : kKnownProcessNames) printf(" %s", name);
            printf(")\n");
            return 2;
        }
        if (*g_matchedProcessName != '\0') {
            printf("[*] target image: %s\n", g_matchedProcessName);
        }

        if (options.methodForced) {
            const InjectionResult result = RunInjection(options, pid);
            return result.success ? 0 : 3;
        }

        LadderOutcome outcome;
        RunLadder(options, pid, outcome);
        if (outcome.verified) {
            printf("[+] Verified rung: %s (%s)\n", InjectionMethodName(outcome.method),
                   InjectionMethodCode(outcome.method));
            return 0;
        }
        printf("[-] No rung verified the payload\n");
        return 3;
    }

    const bool gameFound = (options.explicitPid != 0) ||
                           (FindGameProcessId() != 0);
    printf("[*] %s %s\n",
           (*g_matchedProcessName != '\0') ? g_matchedProcessName : kGameProcessName,
           gameFound ? "detected" : "not running yet");

    InteractiveMenu(options, gameFound);
    return 0;
}
