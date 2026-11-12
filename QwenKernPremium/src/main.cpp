#include <windows.h>
#include <cwchar>        // wcsrchr / wcscat_s for the attach canary path
#include "main.h"        // umbrella: pulls in Application + globals (see main.h)
#include "log.h"         // Logf / LogClose (initialize happens in Application)

// Global application instance
Application* g_pApplication = nullptr;

// ----------------------------------------------------------------------------
// CreateThread's start routine must use the WINAPI (__stdcall) convention.
// A capture-less lambda is __cdecl by default, which caused a C2664 conversion
// error to LPTHREAD_START_ROUTINE.
//
// Initialization also runs on this thread, NOT inside DllMain: Initialize()
// creates a temporary D3D11 device to discover the swap-chain vtable, and
// device creation under the loader lock is a classic deadlock source.
// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
// Early-inject gate.
// A kernel map can only land in the first seconds of a Javelin-protected game: once it is fully
// initialised, allocating inside it fails (0xC000000D at the alloc step, measured). That means this
// thread can run before the renderer exists - InstallHooks() then patches dxgi/d3d12 while they are
// not loaded yet and the game dies at t+0. So wait for the render module first.
// GetModuleHandleW/Sleep are already in the IAT (kernel32), no new import.
// ----------------------------------------------------------------------------
static bool WaitForRenderer(DWORD timeoutMs) {
    const DWORD step = 100;
    for (DWORD waited = 0; waited < timeoutMs; waited += step) {
        if (GetModuleHandleW(L"dxgi.dll")) {
            Sleep(400);   // let the swap-chain vtable settle before touching it
            return true;
        }
        Sleep(step);
    }
    return false;
}

// ----------------------------------------------------------------------------
// Raw attach canary.  Appends one line to `apexcheat_attach.log` NEXT TO THIS
// DLL, using only CreateFileW/WriteFile - no CRT FILE*, no LogInit, no
// %LOCALAPPDATA%.  If every other diagnostic channel is dead (unwritable
// profile, jailed writes, worker thread killed before LogInit), this still says
// "the module got here, at this second, in this pid".  ov73 evidence: the
// console-side hook DLL reported LoadLibraryW success, but no payload log ever
// appeared - the canary splits "module never initialised" from "log channel
// broken" and names the pid, which matters because the loading CONSOLE and the
// GAME are different processes with the same DLL.
// ----------------------------------------------------------------------------
static void RawCanary(const char* what) {
    wchar_t path[MAX_PATH] = { 0 };
    HMODULE mine = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCWSTR>(&RawCanary), &mine) || !mine)
        return;
    GetModuleFileNameW(mine, path, MAX_PATH);
    wchar_t* slash = wcsrchr(path, L'\\');
    if (!slash) return;
    slash[1] = L'\0';
    wcscat_s(path, L"apexcheat_attach.log");

    HANDLE h = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                           nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return;
    SYSTEMTIME now{};
    GetLocalTime(&now);
    char line[256];
    wsprintfA(line, "[%04u-%02u-%02u %02u:%02u:%02u.%03u pid=%lu tid=%lu] %s\r\n",
              now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
              now.wMilliseconds, static_cast<unsigned long>(GetCurrentProcessId()),
              static_cast<unsigned long>(GetCurrentThreadId()), what);
    DWORD wrote = 0;
    WriteFile(h, line, (DWORD) lstrlenA(line), &wrote, nullptr);
    CloseHandle(h);
}

static DWORD WINAPI ApplicationThreadProc(LPVOID /*lpParam*/) {
    if (!g_pApplication) return 0;

    // Open the log FIRST: ov73 showed LoadLibraryW succeeding while no payload
    // log ever appeared, so every later step must be attributed before it can
    // be trusted.  LogInit is idempotent (Initialize() calls it again).
    LogInit(L"payload");
    RawCanary("worker thread entered");
    Logf("[*] payload worker thread up (pid=%lu) - waiting for renderer",
         static_cast<unsigned long>(GetCurrentProcessId()));

    if (!WaitForRenderer(90000))
        Logf("[~] dxgi.dll did not appear within 90 s - initializing anyway");
    else
        Logf("[*] renderer present (dxgi.dll loaded)");

    if (!g_pApplication->Initialize()) {
        RawCanary("Initialize() FAILED");
        Logf("[-] Application initialization failed; payload is inert");
        return 1;
    }
    RawCanary("Initialize() OK - entering main loop");

    g_pApplication->Run();
    RawCanary("main loop exited");
    return 0;
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID /*lpReserved*/) {
    switch (ul_reason_for_call) {
        case DLL_PROCESS_ATTACH: {
            // Disable thread optimization for better compatibility
            DisableThreadLibraryCalls(hModule);
            
            RawCanary("DllMain PROCESS_ATTACH");
            // Create the application; Initialize() runs on the worker thread.
            g_pApplication = new Application();

            // Start the main thread (the canary names which outcome happened)
            if (!CreateThread(nullptr, 0, ApplicationThreadProc, nullptr, 0, nullptr)) {
                RawCanary("CreateThread FAILED - running inline");
                ApplicationThreadProc(nullptr);
            } else {
                RawCanary("CreateThread ok");
            }
            
            break;
        }
        case DLL_PROCESS_DETACH: {
            RawCanary("DllMain PROCESS_DETACH");
            // Cleanup when the DLL is detached
            if (g_pApplication) {
                g_pApplication->Shutdown();
                delete g_pApplication;
                g_pApplication = nullptr;
            }
            break;
        }
    }
    return TRUE;
}