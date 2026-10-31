// ---------------------------------------------------------------------------
//  main.cpp -- ApexCheatMenu entry point
//
//  The menu is drawn by menu_core.cpp onto a transparent, click-through,
//  always-on-top layered window.  Global hotkeys are registered against that
//  window, so INSERT / HOME work no matter which application has focus.
// ---------------------------------------------------------------------------
#include <Windows.h>

#include "menu_core.hpp"

// ---------------------------------------------------------------------------
//  Global menu state (the only definition -- menu_core.cpp uses these)
// ---------------------------------------------------------------------------
bool           g_menuVisible   = true;   // menu starts visible so it can be verified
bool           g_menuActive    = true;
SharedMenuData g_sharedMenuData;
ESPConfig      g_espConfig;

// ---------------------------------------------------------------------------
//  Entry point
// ---------------------------------------------------------------------------
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance,
                   LPSTR lpCmdLine, int nCmdShow)
{
    (void)hPrevInstance;
    (void)lpCmdLine;

    if (!InitializeOverlay(hInstance, nCmdShow))
    {
        MessageBoxW(NULL,
                    L"Failed to initialize the overlay window.\n"
                    L"Make sure no other instance is already running.",
                    L"ApexCheatMenu",
                    MB_OK | MB_ICONERROR);
        return 1;
    }

    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0) > 0)
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    ShutdownOverlay();
    return 0;
}

// ---------------------------------------------------------------------------
//  Exports -- used when the module is built/loaded as a DLL by a wrapper
// ---------------------------------------------------------------------------
extern "C" {

__declspec(dllexport) bool Menu_IsVisible(void)
{
    return g_menuVisible;
}

__declspec(dllexport) void Menu_SetVisible(bool visible)
{
    if (visible != g_menuVisible)
        ToggleMenu();
}

__declspec(dllexport) void Menu_UpdateData(const SharedMenuData* data)
{
    if (data)
        g_sharedMenuData = *data;
}

__declspec(dllexport) const SharedMenuData* Menu_GetData(void)
{
    return &g_sharedMenuData;
}

__declspec(dllexport) HWND Menu_GetWindow(void)
{
    return GetOverlayWindow();
}

} // extern "C"
