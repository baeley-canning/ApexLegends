#include <windows.h>
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
static DWORD WINAPI ApplicationThreadProc(LPVOID /*lpParam*/) {
    if (!g_pApplication) return 0;

    if (!g_pApplication->Initialize()) {
        Logf("[-] Application initialization failed; payload is inert");
        return 1;
    }

    g_pApplication->Run();
    return 0;
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID /*lpReserved*/) {
    switch (ul_reason_for_call) {
        case DLL_PROCESS_ATTACH: {
            // Disable thread optimization for better compatibility
            DisableThreadLibraryCalls(hModule);
            
            // Create the application; Initialize() runs on the worker thread.
            g_pApplication = new Application();

            // Start the main thread
            CreateThread(nullptr, 0, ApplicationThreadProc, nullptr, 0, nullptr);
            
            break;
        }
        case DLL_PROCESS_DETACH: {
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