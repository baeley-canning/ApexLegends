/**
 * Apex Cheat Phase 5 - Main Implementation
 * 
 * Hybrid Python + C++ DLL architecture with D3D11 rendering
 * Pattern: Kernaim/Ignite/Chudvision style internal overlay
 */

#include <Windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <string>
#include <vector>
#include <DirectXMath.h>

using namespace DirectX;

#include "apex_cheat.h"
#include "d3d11_renderer.h"

// ============================================================================
// GLOBAL CONTEXT
// ============================================================================

static HMODULE g_hModule = nullptr;
static CheatConfig g_Config = {};
static D3D11Context g_D3D11Context = {0};
static std::vector<PlayerInfo> g_Players = {};

// ============================================================================
// FORWARD DECLARATIONS
// ============================================================================

LRESULT CALLBACK MenuWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);

// ============================================================================
// MENU WINDOW CLASS
// ============================================================================

static const wchar_t* MENU_CLASS_NAME = L"ApexCheatMenu";

// ============================================================================
// HOTKEY IDs
// ============================================================================

#define HOTKEY_MENU 100
#define HOTKEY_ESP  101

// ============================================================================
// MACRO DEFINITIONS (for C API exports)
// ============================================================================

#define CHEAT_INIT 
#define CHEAT_SHUTDOWN

// ============================================================================
// MENU WINDOW CREATION
// ============================================================================

static HWND CreateMenuWindow(const CheatConfig* config) {
    WNDCLASS wc = {};
    wc.lpfnWndProc = MenuWindowProc;
    wc.hInstance = g_hModule;
    wc.lpszClassName = MENU_CLASS_NAME;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    
    RegisterClass(&wc);

    HWND hwnd = CreateWindowEx(
        WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TRANSPARENT,
        MENU_CLASS_NAME,
        L"Apex Cheat Menu",
        WS_POPUP | WS_VISIBLE,
        config->window_x,
        config->window_y,
        config->window_width,
        config->window_height,
        nullptr,
        nullptr,
        g_hModule,
        nullptr
    );

    // Set layered window attributes for transparency
    SetLayeredWindowAttributes(hwnd, 0, 240, LWA_ALPHA);

    return hwnd;
}

// ============================================================================
// MENU WINDOW PROCEDURE
// ============================================================================

LRESULT CALLBACK MenuWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_CREATE:
            return 0;

        case WM_PAINT: {
            PAINTSTRUCT ps;
            BeginPaint(hwnd, &ps);

            // Draw menu background
            HBRUSH bg_brush = CreateSolidBrush(RGB(26, 26, 46));
            RECT rc;
            GetClientRect(hwnd, &rc);
            FillRect(ps.hdc, &rc, bg_brush);

            // Create and select font for title
            HFONT hFont = CreateFontW(24, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                                      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                      CLEARTYPE_NATURAL_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
            HFONT hOldFont = (HFONT)SelectObject(ps.hdc, hFont);

            // Draw title
            SetTextColor(ps.hdc, RGB(0, 255, 127));
            TextOutW(ps.hdc, 20, 20, L"APEX CHEAT MENU", 17);

            // Create and select font for menu items
            HFONT hFontSmall = CreateFontW(16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                                           DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                           CLEARTYPE_NATURAL_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
            HFONT hOldFontSmall = (HFONT)SelectObject(ps.hdc, hFontSmall);

            // Draw ESP toggle
            SetTextColor(ps.hdc, RGB(255, 255, 255));
            TextOutW(ps.hdc, 30, 80, g_D3D11Context.esp_enabled ? L"ESP: ON" : L"ESP: OFF",
                     g_D3D11Context.esp_enabled ? 9 : 10);

            // Draw Aim toggle
            TextOutW(ps.hdc, 30, 120, g_D3D11Context.aimbot_enabled ? L"AIM: ON" : L"AIM: OFF",
                     g_D3D11Context.aimbot_enabled ? 9 : 10);

            // Cleanup fonts
            SelectObject(ps.hdc, hOldFontSmall);
            DeleteObject(hFontSmall);
            SelectObject(ps.hdc, hOldFont);
            DeleteObject(hFont);

            DeleteObject(bg_brush);
            EndPaint(hwnd, &ps);
            return 0;
        }

        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;

        case WM_HOTKEY:
            switch (HIWORD(wParam)) {
                case HOTKEY_MENU:
                    CheatToggleMenu();
                    return 0;

                case HOTKEY_ESP:
                    CheatToggleESP();
                    return 0;
            }
            return 0;

        case WM_LBUTTONDOWN:
            // Drag window on click
            ReleaseCapture();
            SendMessage(hwnd, WM_SYSCOMMAND, SC_MOVE | 0x2, 0);
            return 0;

        default:
            return DefWindowProc(hwnd, msg, wParam, lParam);
    }
}

// ============================================================================
// PUBLIC C API IMPLEMENTATION
// ============================================================================

extern "C" {

CHEAT_API bool CHEAT_INIT CheatInitialize(HMODULE hModule, CheatConfig* config) {
    g_hModule = hModule;

    // Copy config or use defaults
    if (config) {
        g_Config = *config;
    } else {
        g_Config.menu_enabled = true;
        g_Config.esp_enabled = true;
        g_Config.aimbot_enabled = true;
        g_Config.humanizer_enabled = true;
        g_Config.window_width = DEFAULT_WINDOW_WIDTH;
        g_Config.window_height = DEFAULT_WINDOW_HEIGHT;
        g_Config.window_x = DEFAULT_WINDOW_X;
        g_Config.window_y = DEFAULT_WINDOW_Y;
        g_Config.vsync = true;
        g_Config.transparent_background = true;
        g_Config.always_on_top = true;
        g_Config.menu_hotkey = DEFAULT_MENU_HOTKEY;
        g_Config.esp_hotkey = DEFAULT_ESP_HOTKEY;
    }

    // Initialize D3D11 renderer
    D3D11Config d3d_config = {};
    d3d_config.enable_vsync = g_Config.vsync;
    d3d_config.transparent_background = g_Config.transparent_background;
    d3d_config.always_on_top = g_Config.always_on_top;
    d3d_config.width = g_Config.window_width;
    d3d_config.height = g_Config.window_height;

    if (!D3D11_Init(&g_D3D11Context, &d3d_config)) {
        return false;
    }

    // Create menu window
    if (g_Config.menu_enabled) {
        HWND hwnd = CreateMenuWindow(&g_Config);
        if (!hwnd) {
            return false;
        }
    }

    // Register hotkeys
    CheatRegisterHotkeys();

    // Add some default players for ESP demo
    const char* player_names[] = {
        "Player1", "Player2", "Player3", "Player4", "Player5"
    };
    
    for (int i = 0; i < 5; ++i) {
        PlayerInfo player = {};
        player.name = player_names[i];
        player.x = 100.0f + i * 80.0f;
        player.y = 200.0f;
        player.z = 0.0f;
        player.health = 100 - i * 10;
        player.max_health = 100;
        player.shield = 50;
        player.max_shield = 100;
        player.legend = i % 2 == 0 ? "Lifeline" : "Wraith";
        player.weapon = i % 3 == 0 ? "R-99" : "R-301";
        player.is_enemy = true;
        player.is_knocked = false;
        
        CheatAddPlayer(&player);
    }

    return true;
}

CHEAT_API void CHEAT_SHUTDOWN CheatShutdown(void) {
    // Unregister hotkeys
    CheatUnregisterHotkeys();

    // Shutdown D3D11 renderer
    D3D11_Shutdown(&g_D3D11Context);

    // Destroy menu window if exists
    HWND hwnd = FindWindow(MENU_CLASS_NAME, L"Apex Cheat Menu");
    if (hwnd) {
        DestroyWindow(hwnd);
    }
}

CHEAT_API void CHEAT_API CheatShowMenu(void) {
    HWND hwnd = FindWindow(MENU_CLASS_NAME, L"Apex Cheat Menu");
    if (hwnd) {
        ShowWindow(hwnd, SW_SHOW);
        g_D3D11Context.menu_visible = true;
    }
}

CHEAT_API void CHEAT_API CheatHideMenu(void) {
    HWND hwnd = FindWindow(MENU_CLASS_NAME, L"Apex Cheat Menu");
    if (hwnd) {
        ShowWindow(hwnd, SW_HIDE);
        g_D3D11Context.menu_visible = false;
    }
}

CHEAT_API void CHEAT_API CheatToggleMenu(void) {
    g_D3D11Context.menu_visible = !g_D3D11Context.menu_visible;

    HWND hwnd = FindWindow(MENU_CLASS_NAME, L"Apex Cheat Menu");
    if (hwnd) {
        ShowWindow(hwnd, g_D3D11Context.menu_visible ? SW_SHOW : SW_HIDE);
    }
}

CHEAT_API bool CHEAT_API CheatIsMenuVisible(void) {
    return g_D3D11Context.menu_visible;
}

CHEAT_API void CHEAT_API CheatShowESP(void) {
    g_D3D11Context.esp_enabled = true;
}

CHEAT_API void CHEAT_API CheatHideESP(void) {
    g_D3D11Context.esp_enabled = false;
}

CHEAT_API void CHEAT_API CheatToggleESP(void) {
    g_D3D11Context.esp_enabled = !g_D3D11Context.esp_enabled;
}

CHEAT_API bool CHEAT_API CheatIsESPEnabled(void) {
    return g_D3D11Context.esp_enabled;
}

CHEAT_API void CHEAT_API CheatAddPlayer(PlayerInfo* player) {
    if (player) {
        g_Players.push_back(*player);
    }
}

CHEAT_API void CHEAT_API CheatRemovePlayer(const char* name) {
    if (!name) return;

    for (auto it = g_Players.begin(); it != g_Players.end(); ++it) {
        if (it->name == name) {
            g_Players.erase(it);
            break;
        }
    }
}

CHEAT_API size_t CHEAT_API CheatGetPlayerCount(void) {
    return g_Players.size();
}

CHEAT_API PlayerInfo* CHEAT_API CheatGetPlayer(size_t index) {
    if (index < g_Players.size()) {
        return &g_Players[index];
    }
    return nullptr;
}

CHEAT_API void CHEAT_API CheatRenderFrame(ID3D11DeviceContext* ctx) {
    // Render menu
    D3D11_RenderMenu(&g_D3D11Context, ctx);

    // Render ESP
    D3D11_RenderESP(&g_D3D11Context, ctx);

    g_D3D11Context.frame_count++;
}

CHEAT_API bool CHEAT_API CheatRegisterHotkeys(void) {
    // Register INSERT key for menu toggle
    if (!RegisterHotKey(nullptr, HOTKEY_MENU, 0, g_Config.menu_hotkey)) {
        return false;
    }

    // Register HOME key for ESP toggle
    if (!RegisterHotKey(nullptr, HOTKEY_ESP, 0, g_Config.esp_hotkey)) {
        return false;
    }

    return true;
}

CHEAT_API void CHEAT_API CheatUnregisterHotkeys(void) {
    UnregisterHotKey(nullptr, HOTKEY_MENU);
    UnregisterHotKey(nullptr, HOTKEY_ESP);
}

} // extern "C"

// ============================================================================
// DLL MAIN
// ============================================================================

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
        case DLL_PROCESS_ATTACH:
            break;

        case DLL_THREAD_ATTACH:
            break;

        case DLL_THREAD_DETACH:
            break;

        case DLL_PROCESS_DETACH:
            CheatShutdown();
            break;
    }
    return TRUE;
}

// ============================================================================
// END OF FILE
// ============================================================================
