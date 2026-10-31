#include "injector.h"
#include "manual_map.h"
#include <iostream>
#include <cstdio>
#include <cstring>
#include <psapi.h>
#include <tlhelp32.h>

namespace {

// File name part of a path.  Used to look up the module after injection, which
// matters when the launcher injected a staged copy under a random name.
std::string BaseNameOf(const std::string& path) {
    const size_t slash = path.find_last_of("\\/");
    return (slash == std::string::npos) ? path : path.substr(slash + 1);
}

// Base of `moduleName` inside `pid` (Toolhelp; 0 when the list is unreadable).
ULONGLONG ModuleBaseForPid(DWORD pid, const char* moduleName) {
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

// Address of an export as it exists INSIDE the target: same DLL build, different
// load base (system DLLs are randomised per boot, not per process).
ULONGLONG TargetExportAddress(DWORD pid, const char* moduleName, const char* exportName) {
    HMODULE local = GetModuleHandleA(moduleName);
    if (!local) return 0;

    const ULONGLONG localBase = reinterpret_cast<ULONGLONG>(local);
    const ULONGLONG localExport =
        reinterpret_cast<ULONGLONG>(GetProcAddress(local, exportName));
    const ULONGLONG targetBase = ModuleBaseForPid(pid, moduleName);

    if (localExport == 0 || targetBase == 0) return 0;
    return targetBase + (localExport - localBase);
}

// A4's in-target code: switch to a PRIVATE stack, call LoadLibraryA(path),
// then restore the thread's saved CONTEXT (registers + RIP + RSP) so the
// hijacked thread continues as if nothing happened.  The first instruction
// writes a marker, which is the only way to tell "stub never ran" from
// "stub ran but LoadLibrary refused" without guessing.
std::vector<BYTE> BuildHijackStub(ULONGLONG privateStackTop, ULONGLONG loadLibrary,
                                  ULONGLONG path, ULONGLONG context,
                                  ULONGLONG restoreContext, ULONGLONG marker) {
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

    emit64(0x49, 0xBA, marker);                 // mov r10, marker
    emit({ 0x41, 0xC7, 0x02, 0x01, 0x00, 0x00, 0x00 }); // mov dword ptr [r10], 1
    emit64(0x48, 0xBC, privateStackTop);       // mov rsp, privateStackTop
    emit({ 0x48, 0x83, 0xEC, 0x20 });          // sub rsp, 0x20 (shadow space)
    emit64(0x48, 0xB8, loadLibrary);           // mov rax, LoadLibraryA
    emit64(0x48, 0xB9, path);                  // mov rcx, path
    emit({ 0xFF, 0xD0 });                      // call rax
    emit64(0x48, 0xB9, context);               // mov rcx, &savedContext
    emit({ 0x48, 0x31, 0xD2 });                // xor rdx, rdx
    emit64(0x48, 0xB8, restoreContext);        // mov rax, RtlRestoreContext
    emit({ 0xFF, 0xD0 });                      // call rax (never returns)
    emit({ 0xCC });                            // int3, unreachable
    return code;
}

} // namespace


// ============================================================================
// ApexInjector Implementation — Based on JAVELIN & R5AC RE Findings
// ============================================================================

ApexInjector::ApexInjector() : hTargetProcess_(nullptr) {}

// ============================================================================
// METHOD 1: NtCreateThreadEx Injection (HIDE Strategy)
// Bypasses CreateRemoteThread hooks by using native NT API directly.
// R5AC relevance: produces cleaner stack traces, stays within ntdll.dll 
// whitelist range (+1000 to +119f1e).
// ============================================================================

InjectionResult ApexInjector::InjectViaNtCreateThreadEx(
    DWORD targetPid, const std::string& dllPath)
{
    InjectionResult result{};
    result.success = false;
    result.threadId = 0;
    result.dllBaseAddress = nullptr;

    hTargetProcess_ = OpenProcess(
        PROCESS_CREATE_THREAD | PROCESS_VM_OPERATION | 
        PROCESS_VM_WRITE | PROCESS_QUERY_INFORMATION, FALSE, targetPid);

    if (!hTargetProcess_) {
        result.errorMessage = "OpenProcess failed: " + std::to_string(GetLastError());
        return result;
    }

    size_t dllPathSize = dllPath.size() + 1;
    LPVOID remoteDllPath = VirtualAllocEx(hTargetProcess_, nullptr, dllPathSize, 
        MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);

    if (!remoteDllPath) {
        result.errorMessage = "VirtualAllocEx failed: " + std::to_string(GetLastError());
        CloseHandle(hTargetProcess_);
        return result;
    }

    SIZE_T bytesWritten = 0;
    if (!WriteProcessMemory(hTargetProcess_, remoteDllPath, dllPath.c_str(), 
                            dllPathSize, &bytesWritten)) {
        VirtualFreeEx(hTargetProcess_, remoteDllPath, 0, MEM_RELEASE);
        CloseHandle(hTargetProcess_);
        return result;
    }

    HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
    FARPROC pLoadLibrary = GetProcAddress(hKernel32, "LoadLibraryA");

    if (!pLoadLibrary) {
        VirtualFreeEx(hTargetProcess_, remoteDllPath, 0, MEM_RELEASE);
        CloseHandle(hTargetProcess_);
        return result;
    }

    FNtCreateThreadEx pNtCreateThread = ResolveNtCreateThreadEx();

    if (!pNtCreateThread) {
        // Fallback: use standard CreateRemoteThread
        HANDLE hThread = CreateRemoteThread(hTargetProcess_, nullptr, 0,
            reinterpret_cast<LPTHREAD_START_ROUTINE>(pLoadLibrary), remoteDllPath, 0, nullptr);

        if (hThread) {
            result.success = true;
            result.threadId = GetThreadId(hThread);
            Sleep(500);
            result.dllBaseAddress = GetModuleBase(targetPid, BaseNameOf(dllPath).c_str());
            CloseHandle(hThread);
        } else {
            result.errorMessage = "CreateRemoteThread failed: " + std::to_string(GetLastError());
        }

        VirtualFreeEx(hTargetProcess_, remoteDllPath, 0, MEM_RELEASE);
        CloseHandle(hTargetProcess_);
        return result;
    }

    HANDLE hThread = nullptr;
    // NtCreateThreadEx takes exactly 11 arguments:
    //   (ThreadHandle, DesiredAccess, ObjectAttributes, ProcessHandle, StartRoutine,
    //    Argument, CreateFlags, ZeroBits, StackSize, MaximumStackSize, AttributeList)
    // The previous call passed a 12th (extra) zero => C2660.
    NTSTATUS status = pNtCreateThread(&hThread, THREAD_ALL_ACCESS, nullptr,
        hTargetProcess_, reinterpret_cast<PVOID>(pLoadLibrary), remoteDllPath,
        0, 0, 0, 0, nullptr);

    // STATUS_SUCCESS == 0.  winternl.h does not define the NTSTATUS code
    // macros, and including ntstatus.h conflicts with winnt.h, so compare
    // against the literal (documented) value.
    if (status == 0 && hThread) {
        result.success = true;
        result.threadId = GetThreadId(hThread);
        CloseHandle(hThread);
        Sleep(500);
        result.dllBaseAddress = GetModuleBase(targetPid, BaseNameOf(dllPath).c_str());
        std::cout << "[+] NtCreateThreadEx injection SUCCESS — Thread ID: " 
                  << result.threadId << std::endl;
    } else {
        // std::to_string has no (value, base) overload — C2661. Format explicitly.
        char statusBuffer[32] = { 0 };
        sprintf_s(statusBuffer, sizeof(statusBuffer), "0x%08lX",
                  static_cast<unsigned long>(status));
        result.errorMessage = std::string("NtCreateThreadEx failed with status: ") + statusBuffer;
        if (hThread) CloseHandle(hThread);
    }

    VirtualFreeEx(hTargetProcess_, remoteDllPath, 0, MEM_RELEASE);
    CloseHandle(hTargetProcess_);
    hTargetProcess_ = nullptr;
    return result;
}

// ============================================================================
// METHOD 2: APC Queue Injection (IMPERSONATE Strategy)
// Queues LoadLibrary into an EXISTING game thread. Looks like legitimate work.
// JAVELIN RELEVANCE: Bypasses thread enumeration checks (monitors NEW threads).
// R5AC RELEVANCE: Whitelisted thread already passes module whitelist check.
// ============================================================================

InjectionResult ApexInjector::InjectViaApcQueue(
    DWORD targetPid, const std::string& dllPath)
{
    InjectionResult result{};
    result.success = false;
    result.threadId = 0;
    result.dllBaseAddress = nullptr;

    hTargetProcess_ = OpenProcess(
        PROCESS_CREATE_THREAD | PROCESS_VM_OPERATION | 
        PROCESS_VM_WRITE | PROCESS_QUERY_INFORMATION, FALSE, targetPid);

    if (!hTargetProcess_) {
        result.errorMessage = "OpenProcess failed: " + std::to_string(GetLastError());
        return result;
    }

    auto threadIds = EnumerateThreads(targetPid);
    
    if (threadIds.empty()) {
        result.errorMessage = "No threads found in target process";
        CloseHandle(hTargetProcess_);
        return result;
    }

    size_t dllPathSize = dllPath.size() + 1;
    LPVOID remoteDllPath = VirtualAllocEx(hTargetProcess_, nullptr, dllPathSize, 
        MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);

    if (!remoteDllPath) {
        result.errorMessage = "VirtualAllocEx failed: " + std::to_string(GetLastError());
        CloseHandle(hTargetProcess_);
        return result;
    }

    SIZE_T bytesWritten = 0;
    if (!WriteProcessMemory(hTargetProcess_, remoteDllPath, dllPath.c_str(), 
                            dllPathSize, &bytesWritten)) {
        VirtualFreeEx(hTargetProcess_, remoteDllPath, 0, MEM_RELEASE);
        CloseHandle(hTargetProcess_);
        return result;
    }

    HANDLE hTargetThread = nullptr;
    for (DWORD tid : threadIds) {
        HANDLE hThread = OpenThread(THREAD_ALL_ACCESS, FALSE, tid);
        if (hThread) {
            hTargetThread = hThread;
            break;
        }
    }

    if (!hTargetThread) {
        result.errorMessage = "Could not open target thread";
        VirtualFreeEx(hTargetProcess_, remoteDllPath, 0, MEM_RELEASE);
        CloseHandle(hTargetProcess_);
        return result;
    }

    HMODULE hKernel32 = GetModuleHandleA("kernel32.dll");
    FARPROC pLoadLibrary = GetProcAddress(hKernel32, "LoadLibraryA");

    if (!pLoadLibrary) {
        CloseHandle(hTargetThread);
        VirtualFreeEx(hTargetProcess_, remoteDllPath, 0, MEM_RELEASE);
        CloseHandle(hTargetProcess_);
        return result;
    }

    // Queue APC with LoadLibrary as the callback.
    // The target thread will execute LoadLibrary(dllPath) when it reaches 
    // an alertable state (waiting for I/O, sleep, etc.)
    NTSTATUS status = QueueUserAPC(
        reinterpret_cast<PAPCFUNC>(pLoadLibrary), hTargetThread,
        reinterpret_cast<ULONG_PTR>(remoteDllPath));

    if (status != 0) {
        result.success = true;
        result.threadId = GetThreadId(hTargetThread);
        std::cout << "[+] APC Queue injection SUCCESS — Thread ID: " 
                  << result.threadId << std::endl;
        std::cout << "[+] DLL will load when target thread reaches alertable state" << std::endl;
    } else {
        result.errorMessage = "QueueUserAPC failed: " + std::to_string(GetLastError());
    }

    CloseHandle(hTargetThread);
    VirtualFreeEx(hTargetProcess_, remoteDllPath, 0, MEM_RELEASE);
    CloseHandle(hTargetProcess_);
    hTargetProcess_ = nullptr;
    return result;
}

// ============================================================================
// Utility: Enumerate all threads in a target process (for APC targeting)
// Used to find frequently-called game threads for injection timing
// ============================================================================

std::vector<DWORD> ApexInjector::EnumerateThreads(DWORD targetPid) {
    std::vector<DWORD> threadIds;
    HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (hSnapshot == INVALID_HANDLE_VALUE) return threadIds;

    THREADENTRY32 te{};
    te.dwSize = sizeof(THREADENTRY32);

    if (Thread32First(hSnapshot, &te)) {
        do {
            if (te.th32OwnerProcessID == targetPid) {
                threadIds.push_back(te.th32ThreadID);
            }
        } while (Thread32Next(hSnapshot, &te));
    }

    CloseHandle(hSnapshot);
    return threadIds;
}

// ============================================================================
// Utility: Resolve NtCreateThreadEx from ntdll.dll at runtime
// Avoids static import table to prevent detection via IAT scanning
// ============================================================================

FNtCreateThreadEx ApexInjector::ResolveNtCreateThreadEx() {
    HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
    if (!hNtdll) return nullptr;

    auto pFunc = reinterpret_cast<FNtCreateThreadEx>(
        GetProcAddress(hNtdll, "NtCreateThreadEx"));

    if (pFunc) {
        std::cout << "[+] NtCreateThreadEx resolved from ntdll.dll" << std::endl;
    } else {
        std::cout << "[!] NtCreateThreadEx not found in ntdll.dll" << std::endl;
    }

    return pFunc;
}

// ============================================================================
// Internal: Get module base address from target process
// Uses EnumProcessModules to find our injected DLL's load address
// ============================================================================

HMODULE ApexInjector::GetModuleBase(DWORD pid, const char* moduleName) {
    HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    if (hSnapshot == INVALID_HANDLE_VALUE) return nullptr;

    MODULEENTRY32 me{};
    me.dwSize = sizeof(MODULEENTRY32);

    if (Module32First(hSnapshot, &me)) {
        do {
            if (_stricmp(me.szModule, moduleName) == 0 || 
                _stricmp(me.szExePath, moduleName) == 0) {
                CloseHandle(hSnapshot);
                return me.hModule;
            }
        } while (Module32Next(hSnapshot, &me));
    }

    CloseHandle(hSnapshot);
    return nullptr;
}

// ============================================================================
// Unified dispatch: strategy selection
// ============================================================================

const char* InjectionMethodName(InjectionMethod method) {
    switch (method) {
        case InjectionMethod::NtCreateThreadEx:   return "A2 NtCreateThreadEx (HIDE)";
        case InjectionMethod::ApcQueue:           return "A3 APC Queue (IMPERSONATE)";
        case InjectionMethod::KernelDriver:       return "B3 Kernel Driver (KERNEL)";
        case InjectionMethod::CreateRemoteThread: return "A1 CreateRemoteThread + LoadLibraryA";
        case InjectionMethod::ManualMap:          return "A7 Manual Map (MANUAL)";
        case InjectionMethod::ThreadHijack:       return "A4 Thread Hijack (HIJACK)";
        case InjectionMethod::VadLessMap:         return "A8 VAD-less Map (GHOST)";
        default:                                  return "Unknown";
    }
}

const char* InjectionMethodCode(InjectionMethod method) {
    switch (method) {
        case InjectionMethod::NtCreateThreadEx:   return "A2";
        case InjectionMethod::ApcQueue:           return "A3";
        case InjectionMethod::KernelDriver:       return "B3";
        case InjectionMethod::CreateRemoteThread: return "A1";
        case InjectionMethod::ManualMap:          return "A7";
        case InjectionMethod::ThreadHijack:       return "A4";
        case InjectionMethod::VadLessMap:         return "A8";
        default:                                  return "??";
    }
}

// Rungs the roadmap lists but this build does not carry yet.  The ladder asks
// this so a missing rung is a logged SKIP, not a confusing failure.
bool InjectionMethodImplemented(InjectionMethod method) {
    switch (method) {
        case InjectionMethod::NtCreateThreadEx:
        case InjectionMethod::ApcQueue:
        case InjectionMethod::KernelDriver:
        case InjectionMethod::CreateRemoteThread:
        case InjectionMethod::ManualMap:
        case InjectionMethod::ThreadHijack:
            return true;
        case InjectionMethod::VadLessMap:
        default:
            return false;
    }
}

// ============================================================================
// METHOD A1: CreateRemoteThread + LoadLibraryA (baseline rung)
//
// Kept separate from A2 instead of sharing its fallback path: the ladder needs
// an honest A1 measurement, and A2's built-in fallback would silently turn an
// A2 failure into an "A2 success".
// ============================================================================

InjectionResult ApexInjector::InjectViaCreateRemoteThread(DWORD targetPid,
                                                         const std::string& dllPath) {
    InjectionResult result{};
    result.success = false;
    result.threadId = 0;
    result.dllBaseAddress = nullptr;

    HANDLE process = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_VM_OPERATION |
                                 PROCESS_VM_WRITE | PROCESS_QUERY_INFORMATION,
                                 FALSE, targetPid);
    if (!process) {
        result.errorMessage = "OpenProcess failed: " + std::to_string(GetLastError());
        return result;
    }

    const SIZE_T pathBytes = dllPath.size() + 1;
    void* remotePath = VirtualAllocEx(process, nullptr, pathBytes,
                                      MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remotePath) {
        result.errorMessage = "VirtualAllocEx failed: " + std::to_string(GetLastError());
        CloseHandle(process);
        return result;
    }

    SIZE_T written = 0;
    if (!WriteProcessMemory(process, remotePath, dllPath.c_str(), pathBytes, &written)) {
        result.errorMessage = "WriteProcessMemory failed: " + std::to_string(GetLastError());
        VirtualFreeEx(process, remotePath, 0, MEM_RELEASE);
        CloseHandle(process);
        return result;
    }

    FARPROC loadLibrary = GetProcAddress(GetModuleHandleA("kernel32.dll"), "LoadLibraryA");
    if (!loadLibrary) {
        result.errorMessage = "kernel32!LoadLibraryA not resolved";
        VirtualFreeEx(process, remotePath, 0, MEM_RELEASE);
        CloseHandle(process);
        return result;
    }

    HANDLE thread = CreateRemoteThread(process, nullptr, 0,
                                       reinterpret_cast<LPTHREAD_START_ROUTINE>(loadLibrary),
                                       remotePath, 0, nullptr);
    if (!thread) {
        result.errorMessage = "CreateRemoteThread failed: " + std::to_string(GetLastError());
        VirtualFreeEx(process, remotePath, 0, MEM_RELEASE);
        CloseHandle(process);
        return result;
    }

    // Wait: LoadLibraryA returns the module base as the thread exit code, which
    // is a genuine load verdict, not a "we managed to spawn a thread" verdict.
    const DWORD wait = WaitForSingleObject(thread, 10000);
    DWORD moduleBase = 0;
    GetExitCodeThread(thread, &moduleBase);

    if (wait == WAIT_OBJECT_0 && moduleBase != 0) {
        result.success = true;
        result.dllBaseAddress = reinterpret_cast<HMODULE>(static_cast<ULONG_PTR>(moduleBase));
        result.threadId = GetThreadId(thread);
    } else if (wait == WAIT_OBJECT_0) {
        result.errorMessage = "remote LoadLibraryA returned NULL (DllMain or dependency failed)";
    } else {
        result.errorMessage = "remote thread did not finish in 10s";
    }

    CloseHandle(thread);
    VirtualFreeEx(process, remotePath, 0, MEM_RELEASE);
    CloseHandle(process);
    return result;
}

// ============================================================================
// METHOD A4: thread hijack ("HIJACK")
//
// No new thread and no APC: suspend an existing thread, point it at a stub on a
// PRIVATE stack, let the stub call LoadLibraryA, then restore the saved CONTEXT
// through RtlRestoreContext.  Every register (volatile included), RIP and RSP
// come back, so the thread continues exactly where it was suspended - the
// difference between this and the classic "clobber the thread" hijack.
//
// Cost: the target must allow PAGE_EXECUTE* allocation (measurement X2 on the
// live game says Javelin/AGC refuses it, in which case the rung reports the
// exact win32 error instead of guessing).
// ============================================================================

InjectionResult ApexInjector::InjectViaThreadHijack(DWORD targetPid,
                                                    const std::string& dllPath) {
    InjectionResult result{};
    result.success = false;
    result.threadId = 0;
    result.dllBaseAddress = nullptr;

    HANDLE process = OpenProcess(
        PROCESS_CREATE_THREAD | PROCESS_VM_OPERATION | PROCESS_VM_WRITE |
            PROCESS_VM_READ | PROCESS_QUERY_INFORMATION,
        FALSE, targetPid);
    if (!process) {
        result.errorMessage = "OpenProcess failed: " + std::to_string(GetLastError());
        return result;
    }

    const ULONGLONG remoteLoadLibrary =
        TargetExportAddress(targetPid, "kernel32.dll", "LoadLibraryA");
    const ULONGLONG remoteRestore =
        TargetExportAddress(targetPid, "ntdll.dll", "RtlRestoreContext");

    if (remoteLoadLibrary == 0 || remoteRestore == 0) {
        result.errorMessage =
            "target kernel32/ntdll base unreadable (module list denied)";
        CloseHandle(process);
        return result;
    }

    const size_t pathSize = dllPath.size() + 1;
    void* remotePath = VirtualAllocEx(process, nullptr, pathSize,
                                      MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remotePath) {
        result.errorMessage = "VirtualAllocEx(path) failed: " + std::to_string(GetLastError());
        CloseHandle(process);
        return result;
    }

    SIZE_T written = 0;
    if (!WriteProcessMemory(process, remotePath, dllPath.c_str(), pathSize, &written)) {
        result.errorMessage = "WriteProcessMemory(path) failed: " + std::to_string(GetLastError());
        VirtualFreeEx(process, remotePath, 0, MEM_RELEASE);
        CloseHandle(process);
        return result;
    }

    // A thread suspended inside a kernel wait ignores the new user context until
    // the wait completes (measured: 8/9 threads reported stub-ran=no, the one in
    // user mode worked), so A4 walks the thread list.  Every attempt gets its
    // OWN block - stub + that thread's saved CONTEXT + private stack.  Sharing
    // one CONTEXT slot would let an earlier, still-pending thread restore the
    // LAST thread's registers.
    const size_t blockSize = 0x2000;
    const int kMaxAttempts = 40;   // threads in a wait are common: walk them all
    const std::vector<DWORD> threads = EnumerateThreads(targetPid);
    const std::string moduleName = BaseNameOf(dllPath);

    int tried = 0;
    int stubRan = 0;
    DWORD lastMarker = 0;

    for (size_t i = 0; i < threads.size() && tried < kMaxAttempts; ++i) {
        const DWORD tid = threads[i];
        HANDLE thread = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT |
                                       THREAD_SET_CONTEXT | THREAD_QUERY_INFORMATION,
                                   FALSE, tid);
        if (!thread) continue;

        if (SuspendThread(thread) == static_cast<DWORD>(-1)) {
            CloseHandle(thread);
            continue;
        }

        CONTEXT context{};
        context.ContextFlags = CONTEXT_FULL;
        if (!GetThreadContext(thread, &context) || context.Rip == 0 || context.Rsp == 0) {
            ResumeThread(thread);
            CloseHandle(thread);
            continue;
        }

        BYTE* block = static_cast<BYTE*>(VirtualAllocEx(process, nullptr, blockSize,
                                                        MEM_COMMIT | MEM_RESERVE,
                                                        PAGE_EXECUTE_READWRITE));
        if (!block) {
            ResumeThread(thread);
            CloseHandle(thread);
            break;
        }

        const ULONGLONG originalRip = context.Rip;
        BYTE* contextAddress = block + 0x100;
        BYTE* markerAddress  = block + 0xF80;
        const ULONGLONG stackTop =
            reinterpret_cast<ULONGLONG>(block) + blockSize - 0x10;

        const std::vector<BYTE> stub = BuildHijackStub(
            stackTop, remoteLoadLibrary, reinterpret_cast<ULONGLONG>(remotePath),
            reinterpret_cast<ULONGLONG>(contextAddress), remoteRestore,
            reinterpret_cast<ULONGLONG>(markerAddress));

        SIZE_T blockWritten = 0;
        if (!WriteProcessMemory(process, block, stub.data(), stub.size(), &blockWritten)) {
            ResumeThread(thread);
            CloseHandle(thread);
            break;
        }
        FlushInstructionCache(process, block, stub.size());

        SIZE_T contextWritten = 0;
        if (!WriteProcessMemory(process, contextAddress, &context, sizeof(context),
                                &contextWritten)) {
            ResumeThread(thread);
            CloseHandle(thread);
            continue;
        }

        context.Rip = reinterpret_cast<ULONGLONG>(block);
        context.Rsp = stackTop;

        if (!SetThreadContext(thread, &context)) {
            ResumeThread(thread);
            CloseHandle(thread);
            continue;
        }
        ResumeThread(thread);
        ++tried;

        // The stub restores the thread itself, so a rung that does not deliver
        // can move on to the next thread without leaving it hijacked.  The
        // marker separates "the stub never ran" (thread was in a kernel wait)
        // from "the stub ran and LoadLibrary said no".
        const DWORD start = GetTickCount();
        while (!IsModuleLoaded(targetPid, moduleName.c_str()) &&
               GetTickCount() - start < 250) {
            Sleep(25);
        }

        DWORD marker = 0;
        SIZE_T markerRead = 0;
        ReadProcessMemory(process, markerAddress, &marker, sizeof(marker), &markerRead);
        lastMarker = marker;
        if (marker == 1) ++stubRan;

        const bool loaded = IsModuleLoaded(targetPid, moduleName.c_str());
        printf("[A4]       thread %lu (RIP 0x%llX): stub-ran=%s module=%s\n",
               static_cast<unsigned long>(tid),
               static_cast<unsigned long long>(originalRip),
               marker == 1 ? "yes" : "no", loaded ? "yes" : "no");

        if (loaded) {
            result.success       = true;
            result.threadId      = tid;
            result.dllBaseAddress = GetModuleBase(targetPid, moduleName.c_str());
            result.errorMessage.clear();
            CloseHandle(thread);
            break;
        }

        CloseHandle(thread);
    }

    if (!result.success) {
        char message[256] = { 0 };
        sprintf_s(message, sizeof(message),
                  "hijacked %d thread(s), stub ran on %d, %s never loaded (marker 0x%08lX)",
                  tried, stubRan, moduleName.c_str(),
                  static_cast<unsigned long>(lastMarker));
        result.errorMessage = message;

        // Only safe to free when no thread could have been pointed at the stub.
        // Once a thread's RIP is our stub - or a suspended thread is still
        // pending on one - freeing the page under it would be a race, so an
        // attempted hijack deliberately leaves its block mapped.
        if (tried == 0) {
            VirtualFreeEx(process, remotePath, 0, MEM_RELEASE);
        }
    }

    CloseHandle(process);
    return result;
}

// ============================================================================
// METHOD A7: manual map — thin wrapper around ManualMapper (src\manual_map.cpp)
//
// The verdict is NOT the module list: a manual-mapped payload is deliberately
// absent from it.  result.moduleListVerdict=false tells the ladder to verify
// the mapped image + the entry-point call instead.
// ============================================================================

InjectionResult ApexInjector::InjectViaManualMap(DWORD targetPid,
                                                 const std::string& dllPath) {
    InjectionResult result{};
    result.success            = false;
    result.threadId           = 0;
    result.dllBaseAddress     = nullptr;
    result.moduleListVerdict  = false;
    result.entryExecuted      = false;

    const ManualMapper::MapResult mapped = ManualMapper::Map(targetPid, dllPath);
    result.dllBaseAddress = reinterpret_cast<HMODULE>(
        static_cast<ULONG_PTR>(mapped.imageBase));
    result.threadId      = mapped.threadId;
    result.entryExecuted = mapped.entryExecuted;
    result.success       = mapped.success;

    if (!mapped.success) {
        result.errorMessage = mapped.error.empty() ? "manual map failed" : mapped.error;
    } else {
        std::cout << "[+] Manual map complete at 0x" << std::hex << mapped.imageBase
                  << std::dec << " (payload absent from the module list by design)"
                  << std::endl;
    }
    return result;
}

// ============================================================================
// Utility: is the payload module actually present in the target?
// ============================================================================
bool ApexInjector::IsModuleLoaded(DWORD pid, const char* moduleName) {
    if (!moduleName || !*moduleName) return false;

    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
    if (snapshot == INVALID_HANDLE_VALUE) return false;

    MODULEENTRY32 entry{};
    entry.dwSize = sizeof(entry);

    bool found = false;
    if (Module32First(snapshot, &entry)) {
        do {
            if (_stricmp(entry.szModule, moduleName) == 0) { found = true; break; }
        } while (Module32Next(snapshot, &entry));
    }

    CloseHandle(snapshot);
    return found;
}

InjectionResult ApexInjector::Inject(DWORD targetPid, const std::string& dllPath,
                                     InjectionMethod method,
                                     const std::string& driverPath) {
    std::cout << "[*] Injection strategy: " << InjectionMethodName(method) << std::endl;

    switch (method) {
        case InjectionMethod::NtCreateThreadEx:
            return InjectViaNtCreateThreadEx(targetPid, dllPath);

        case InjectionMethod::ApcQueue:
            return InjectViaApcQueue(targetPid, dllPath);

        case InjectionMethod::KernelDriver:
            return InjectViaKernelDriver(targetPid, dllPath, driverPath);

        case InjectionMethod::CreateRemoteThread:
            return InjectViaCreateRemoteThread(targetPid, dllPath);

        case InjectionMethod::ManualMap:
            return InjectViaManualMap(targetPid, dllPath);

        case InjectionMethod::ThreadHijack:
            return InjectViaThreadHijack(targetPid, dllPath);

        case InjectionMethod::VadLessMap: {
            InjectionResult notBuilt{};
            notBuilt.success = false;
            notBuilt.threadId = 0;
            notBuilt.dllBaseAddress = nullptr;
            notBuilt.errorMessage = "A8 (VAD-less map) is declared but not implemented";
            return notBuilt;
        }

        default: {
            InjectionResult invalid{};
            invalid.success = false;
            invalid.threadId = 0;
            invalid.dllBaseAddress = nullptr;
            invalid.errorMessage = "Unsupported injection method";
            return invalid;
        }
    }
}



