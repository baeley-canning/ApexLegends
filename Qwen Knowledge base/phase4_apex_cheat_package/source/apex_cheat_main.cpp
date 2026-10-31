/**
 * Apex Cheat - Main Implementation
 *
 * Chudvision/Ignite/Kernaim style internal overlay with D3D11 rendering
 * Features: Triggerbot Humanization, Legend-Adaptive Aimbot, ESP Rendering
 */

#include <Windows.h>
#include <tchar.h>
#include <d3d11.h>
#include <string>
#include <vector>
#include <map>
#include <random>

#include "apex_cheat.h"
#include "d3d11_renderer.h"

// ============================================================================
// GLOBAL CONTEXT
// ============================================================================

static HMODULE g_hModule = nullptr;
static CheatConfig g_Config = {};
static D3D11Context g_D3D11Context = {0};
static std::vector<PlayerInfo> g_Players = {};

// Aimbot state
static bool g_AimbotEnabled = true;
static float g_FOV = 10.0f;
static int g_TriggerDelay = 100;

// Triggerbot state  
static bool g_TriggerbotEnabled = true;
static std::mt19937 g_Rng(std::random_device{}());

// Weapon tracking state
static bool g_WeaponTrackingEnabled = true;
static std::string g_CurrentWeapon = "R-99";

// ============================================================================
// FORWARD DECLARATIONS
// ============================================================================

LRESULT CALLBACK MenuWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);

// SetFont declaration (for GDI text rendering)
void SetFont(HDC hdc, int size);

// ============================================================================
// MENU WINDOW CLASS
// ============================================================================

static const wchar_t* MENU_CLASS_NAME = L"ApexCheatMenu";

// ============================================================================
// HOTKEY IDs
// ============================================================================

#define HOTKEY_MENU 100
#define HOTKEY_ESP  101
#define HOTKEY_AIM  102

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
    SetLayeredWindowAttributes(hwnd, RGB(0, 0, 0), (uint8_t)(240 * g_D3D11Context.menu_alpha), LWA_ALPHA | LWA_COLORKEY);

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
            DeleteObject(bg_brush);

            // Draw title
            SetTextColor(ps.hdc, RGB(0, 255, 127));
            SetFont(ps.hdc, 24);
            TextOutW(ps.hdc, 20, 20, L"APEX CHEAT MENU", 17);

            // Draw ESP toggle
            SetTextColor(ps.hdc, RGB(255, 255, 255));
            SetFont(ps.hdc, 16);
            TextOutW(ps.hdc, 30, 80, g_D3D11Context.esp_enabled ? L"ESP: ON" : L"ESP: OFF",
                     g_D3D11Context.esp_enabled ? 9 : 10);

            // Draw Aim toggle
            TextOutW(ps.hdc, 30, 120, g_D3D11Context.aimbot_enabled ? L"AIM: ON" : L"AIM: OFF",
                     g_D3D11Context.aimbot_enabled ? 9 : 10);

            // Draw humanizer indicator
            TextOutW(ps.hdc, 30, 160, g_Config.humanizer_enabled ? L"HUMANIZER: ON" : L"HUMANIZER: OFF",
                     g_Config.humanizer_enabled ? 12 : 13);

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

                case HOTKEY_AIM:
                    CheatToggleAimbot();
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
// TRIGGERBOT HUMANIZATION IMPLEMENTATION
// ============================================================================

/**
 * Get reaction delay with humanization (50-150ms range)
 */
int CheatGetReactionDelayInternal(void) {
    static std::random_device rd;
    static std::mt19937 gen(rd());
    static std::uniform_int_distribution<> dist(
        g_D3D11Context.triggerbot_config.min_reaction_ms,
        g_D3D11Context.triggerbot_config.max_reaction_ms
    );

    int base_delay = dist(gen);

    // Apply weapon-specific multiplier
    int final_delay = (int)(base_delay * g_D3D11Context.triggerbot_config.weapon_delay_multiplier);

    return final_delay;
}

/**
 * Get micro-jitter value for human-like firing patterns
 */
float CheatGetMicroJitterInternal(void) {
    static std::random_device rd;
    static std::mt19937 gen(rd());
    static std::normal_distribution<> jitter_dist(0.0f, g_D3D11Context.triggerbot_config.micro_jitter_std);

    return jitter_dist(gen);
}

// ============================================================================
// LEGEND-ADAPTIVE AIMBOT IMPLEMENTATION
// ============================================================================

/**
 * Add or update legend-specific aimbot settings
 */
void CheatAddLegendSettingsInternal(LegendSettings* settings) {
    if (settings) {
        g_D3D11Context.legend_settings[settings->legend_name] = *settings;
    }
}

/**
 * Get legend-specific settings for aimbot calculations
 */
LegendSettings* CheatGetLegendSettingsInternal(const char* legend_name) {
    auto it = g_D3D11Context.legend_settings.find(legend_name);
    if (it != g_D3D11Context.legend_settings.end()) {
        return &it->second;
    }
    return nullptr;
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

    const char* legends[] = {"Wraith", "Gibraltar", "Lifeline", "Newcastle", "Bangalore"};
    const char* weapons[] = {"R-99", "R-301", "Wingman", "Sentinel", "Peacekeeper"};

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
        player.legend = legends[i % 5];
        player.weapon = weapons[i % 5];
        player.is_enemy = true;
        player.is_knocked = false;
        player.distance = 50.0f + i * 20.0f;

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

CHEAT_API void CheatShowMenu(void) {
    HWND hwnd = FindWindow(MENU_CLASS_NAME, L"Apex Cheat Menu");
    if (hwnd) {
        ShowWindow(hwnd, SW_SHOW);
        g_D3D11Context.menu_visible = true;
    }
}

CHEAT_API void CheatHideMenu(void) {
    HWND hwnd = FindWindow(MENU_CLASS_NAME, L"Apex Cheat Menu");
    if (hwnd) {
        ShowWindow(hwnd, SW_HIDE);
        g_D3D11Context.menu_visible = false;
    }
}

CHEAT_API void CheatToggleMenu(void) {
    g_D3D11Context.menu_visible = !g_D3D11Context.menu_visible;

    HWND hwnd = FindWindow(MENU_CLASS_NAME, L"Apex Cheat Menu");
    if (hwnd) {
        ShowWindow(hwnd, g_D3D11Context.menu_visible ? SW_SHOW : SW_HIDE);
    }
}

CHEAT_API bool CHEAT_API CheatIsMenuVisible(void) {
    return g_D3D11Context.menu_visible;
}

CHEAT_API void CheatShowESP(void) {
    g_D3D11Context.esp_enabled = true;
}

CHEAT_API void CheatHideESP(void) {
    g_D3D11Context.esp_enabled = false;
}

CHEAT_API void CheatToggleESP(void) {
    g_D3D11Context.esp_enabled = !g_D3D11Context.esp_enabled;
}

CHEAT_API bool CHEAT_API CheatIsESPEnabled(void) {
    return g_D3D11Context.esp_enabled;
}

CHEAT_API void CheatEnableAimbot(void) {
    g_D3D11Context.aimbot_enabled = true;
}

CHEAT_API void CheatDisableAimbot(void) {
    g_D3D11Context.aimbot_enabled = false;
}

CHEAT_API void CheatToggleAimbot(void) {
    g_D3D11Context.aimbot_enabled = !g_D3D11Context.aimbot_enabled;
}

CHEAT_API bool CHEAT_API CheatIsAimbotEnabled(void) {
    return g_D3D11Context.aimbot_enabled;
}

CHEAT_API void CheatAddPlayer(PlayerInfo* player) {
    if (player) {
        g_Players.push_back(*player);
        g_D3D11Context.players.push_back(*player);
    }
}

CHEAT_API void CheatRemovePlayer(const char* name) {
    if (!name) return;

    // Remove from both vectors
    for (auto it = g_Players.begin(); it != g_Players.end(); ++it) {
        if (it->name == name) {
            g_Players.erase(it);
            break;
        }
    }

    for (auto it = g_D3D11Context.players.begin();
         it != g_D3D11Context.players.end(); ++it) {
        if (it->name == name) {
            g_D3D11Context.players.erase(it);
            break;
        }
    }
}

CHEAT_API size_t CheatGetPlayerCount(void) {
    return g_Players.size();
}

CHEAT_API PlayerInfo* CheatGetPlayer(size_t index) {
    if (index < g_Players.size()) {
        return &g_Players[index];
    }
    return nullptr;
}

CHEAT_API void CheatAddLegendSettings(LegendSettings* settings) {
    CheatAddLegendSettingsInternal(settings);
}

CHEAT_API LegendSettings* CheatGetLegendSettings(const char* legend_name) {
    return CheatGetLegendSettingsInternal(legend_name);
}

CHEAT_API void CheatUpdateLegendSettings(const char* legend_name, LegendSettings* settings) {
    if (legend_name && settings) {
        auto it = g_D3D11Context.legend_settings.find(legend_name);
        if (it != g_D3D11Context.legend_settings.end()) {
            it->second = *settings;
        } else {
            g_D3D11Context.legend_settings[legend_name] = *settings;
        }
    }
}

CHEAT_API void CheatSetTriggerbotConfig(TriggerbotConfig* config) {
    if (config) {
        g_D3D11Context.triggerbot_config = *config;
    }
}

CHEAT_API TriggerbotConfig* CheatGetTriggerbotConfig(void) {
    return &g_D3D11Context.triggerbot_config;
}

CHEAT_API void CheatRenderFrame(ID3D11DeviceContext* ctx) {
    // Render menu
    D3D11_RenderMenu(&g_D3D11Context, ctx);

    // Render ESP
    D3D11_RenderESP(&g_D3D11Context, ctx);

    // Render aimbot indicators
    if (g_Config.aimbot_enabled) {
        D3D11_RenderAimbot(&g_D3D11Context, ctx);
    }

    g_D3D11Context.frame_count++;
}

CHEAT_API void CheatPresentFrame(bool vsync) {
    D3D11_Present(&g_D3D11Context, vsync);
}

CHEAT_API bool CheatRegisterHotkeys(void) {
    // Register INSERT key for menu toggle
    if (!RegisterHotKey(nullptr, HOTKEY_MENU, 0, g_Config.menu_hotkey)) {
        return false;
    }

    // Register HOME key for ESP toggle
    if (!RegisterHotKey(nullptr, HOTKEY_ESP, 0, g_Config.esp_hotkey)) {
        return false;
    }

    // Register F1 for aimbot toggle
    if (!RegisterHotKey(nullptr, HOTKEY_AIM, 0, VK_F1)) {
        return false;
    }

    return true;
}

CHEAT_API void CheatUnregisterHotkeys(void) {
    UnregisterHotKey(nullptr, HOTKEY_MENU);
    UnregisterHotKey(nullptr, HOTKEY_ESP);
    UnregisterHotKey(nullptr, HOTKEY_AIM);
}

CHEAT_API int CheatGetReactionDelay(void) {
    return CheatGetReactionDelayInternal();
}

CHEAT_API float CheatGetMicroJitter(void) {
    return CheatGetMicroJitterInternal();
}

// ============================================================================
// NEW PHASE 4 ENHANCED FEATURES
// ============================================================================

/**
 * Initialize cheat with configuration
 */
CHEAT_API void CHEAT_API Initialize(CheatConfig* config) {
    if (config) {
        g_Config = *config;
    }
    
    g_AimbotEnabled = true;
    g_TriggerbotEnabled = true;
    g_WeaponTrackingEnabled = true;
    g_FOV = 10.0f;
    g_TriggerDelay = 100;
}

/**
 * Update cheat state each frame
 */
CHEAT_API void CHEAT_API Update(void) {
    // Aimbot tracking
    if (g_AimbotEnabled && !g_Players.empty()) {
        // Find closest enemy in FOV
        PlayerInfo* target = nullptr;
        float min_dist = g_FOV;

        for (auto& player : g_Players) {
            if (player.is_enemy && player.distance <= min_dist) {
                target = &player;
                min_dist = player.distance;
            }
        }

        // Apply aimbot to target
        if (target) {
            // Aim calculation here
        }
    }

    // Triggerbot check
    if (g_TriggerbotEnabled) {
        // Reaction delay with humanization
        std::uniform_int_distribution<> dist(50, 150);
        int reaction = dist(g_Rng);
        
        // Apply weapon-specific multiplier
        float weapon_mult = 1.0f;
        if (g_CurrentWeapon == "R-99") weapon_mult = 0.9f;
        else if (g_CurrentWeapon == "R-301") weapon_mult = 1.1f;
        
        int final_delay = (int)(reaction * weapon_mult);
    }

    // Weapon tracking update
    if (g_WeaponTrackingEnabled) {
        // Update weapon-specific settings
    }
}

/**
 * Shutdown cheat and cleanup resources
 */
CHEAT_API void CHEAT_API Shutdown(void) {
    g_AimbotEnabled = false;
    g_TriggerbotEnabled = false;
    g_WeaponTrackingEnabled = false;
}

/**
 * Toggle aimbot on/off
 */
CHEAT_API void CHEAT_API ToggleAimbot(void) {
    g_AimbotEnabled = !g_AimbotEnabled;
}

/**
 * Toggle triggerbot on/off
 */
CHEAT_API void CHEAT_API ToggleTriggerbot(void) {
    g_TriggerbotEnabled = !g_TriggerbotEnabled;
}

/**
 * Toggle weapon tracking on/off
 */
CHEAT_API void CHEAT_API ToggleWeaponTracking(void) {
    g_WeaponTrackingEnabled = !g_WeaponTrackingEnabled;
}

/**
 * Toggle ESP overlay on/off
 */
CHEAT_API void CHEAT_API ToggleESP(void) {
    CheatToggleESP();
}

/**
 * Get current cheat status as string
 */
CHEAT_API const char* CHEAT_API GetStatus(void) {
    static char status[256];
    snprintf(status, sizeof(status),
        "Aimbot: %s | Triggerbot: %s | Weapon Tracking: %s",
        g_AimbotEnabled ? "ON" : "OFF",
        g_TriggerbotEnabled ? "ON" : "OFF",
        g_WeaponTrackingEnabled ? "ON" : "OFF");
    return status;
}

/**
 * Set aimbot field of view
 */
CHEAT_API void CHEAT_API SetFOV(int fov) {
    g_FOV = (float)fov;
}

/**
 * Set triggerbot delay in milliseconds
 */
CHEAT_API void CHEAT_API SetTriggerDelay(int delay_ms) {
    g_TriggerDelay = delay_ms;
}

/**
 * Set ESP distance limit in meters
 */
CHEAT_API void CHEAT_API SetESPDistance(int distance) {
    g_D3D11Context.esp_distance_limit = (float)distance;
}

} // extern "C"

// ============================================================================
// SETFONT IMPLEMENTATION (for GDI text rendering)
// ============================================================================

void SetFont(HDC hdc, int size) {
    // Create font with specified size
    LOGFONT lf = {};
    lf.lfHeight = -size;
    lf.lfWidth = 0;
    lf.lfWeight = FW_NORMAL;
    lf.lfItalic = FALSE;
    lf.lfUnderline = FALSE;
    lf.lfStrikeOut = FALSE;
    lf.lfCharSet = DEFAULT_CHARSET;
    lf.lfOutPrecision = OUT_DEFAULT_PRECIS;
    lf.lfClipPrecision = CLIP_DEFAULT_PRECIS;
    lf.lfQuality = DEFAULT_QUALITY;
    lf.lfPitchAndFamily = DEFAULT_PITCH | FF_DONTCARE;
    _tcscpy_s(lf.lfFaceName, _T("Segoe UI"));

    HFONT hFont = CreateFontIndirect(&lf);
    if (hFont) {
        SelectObject(hdc, hFont);
        DeleteObject(hFont);
    }
}

// ============================================================================
// DLL MAIN
// ============================================================================

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
        case DLL_PROCESS_ATTACH:
            DisableThreadLibraryCalls(hModule);
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
