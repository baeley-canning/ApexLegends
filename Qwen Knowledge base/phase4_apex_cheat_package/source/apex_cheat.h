/**
 * Apex Cheat - Chudvision/Ignite/Kernaim Style Internal Overlay
 *
 * C++ DLL with D3D11 rendering for low detection risk on Javelin anti-cheat
 * Features: Triggerbot Humanization, Legend-Adaptive Aimbot, ESP Rendering
 */

#pragma once

#ifndef __APEX_CHEAT_H__
#define __APEX_CHEAT_H__

// ============================================================================
// INCLUDES
// ============================================================================

#include <Windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <string>
#include <vector>
#include <map>
#include <xmmintrin.h>

// ============================================================================
// VERSION
// ============================================================================

#define CHEAT_VERSION_MAJOR   1
#define CHEAT_VERSION_MINOR   0
#define CHEAT_VERSION_BUILD   0

#define CHEAT_VERSION_STRING  "1.0.0"

// ============================================================================
// EXPORTS
// ============================================================================

#ifdef APEX_CHEAT_EXPORTS
    #define CHEAT_API __declspec(dllexport)
    #define CHEAT_INIT   // Empty for export
    #define CHEAT_SHUTDOWN   // Empty for export
#else
    #define CHEAT_API __declspec(dllimport)
    #define CHEAT_INIT   // Empty for import
    #define CHEAT_SHUTDOWN   // Empty for import
#endif

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

// Configuration structure
typedef struct _CheatConfig {
    // Menu settings
    bool menu_enabled;
    bool esp_enabled;
    bool aimbot_enabled;
    bool humanizer_enabled;

    // Window settings
    uint32_t window_width;
    uint32_t window_height;
    int32_t  window_x;
    int32_t  window_y;

    // Rendering settings
    bool vsync;
    bool transparent_background;
    bool always_on_top;

    // Hotkeys
    uint32_t menu_hotkey;
    uint32_t esp_hotkey;
} CheatConfig;

// Player information for ESP
typedef struct _PlayerInfo {
    std::string name;
    float x, y, z;                    // World position
    int health;
    int max_health;
    int shield;
    int max_shield;
    std::string legend;
    std::string weapon;
    bool is_enemy;
    bool is_knocked;
    float distance;                   // Distance to player
} PlayerInfo;

// Legend-specific aimbot settings
typedef struct _LegendSettings {
    std::string legend_name;
    float fov_degrees;                // Aim FOV in degrees
    float smoothing;                  // Aim smoothing factor (0.1-1.0)
    int bone_priority;                // 0=Head, 1=Neck, 2=Chest, 3=Pelvis
    float recoil_reduction;           // 0.0-1.0
    float prediction_factor;          // Target prediction
} LegendSettings;

// Triggerbot settings with humanization
typedef struct _TriggerbotConfig {
    bool enabled;
    int base_reaction_ms;             // Base reaction time (50-150ms)
    int min_reaction_ms;              // Minimum reaction time
    int max_reaction_ms;              // Maximum reaction time
    float weapon_delay_multiplier;    // Weapon-specific delay
    float micro_jitter_std;           // Standard deviation for micro-jitter (degrees)
    bool hold_fire_until_acquired;    // Hold fire until target acquired
} TriggerbotConfig;

// ============================================================================
// FUNCTION TYPES
// ============================================================================

typedef void (*CheatCallback)(void*);

// ============================================================================
// C API EXPORTS
// ============================================================================

extern "C" {
    // Initialization
    CHEAT_API bool CHEAT_INIT CheatInitialize(HMODULE hModule, CheatConfig* config);
    CHEAT_API void CHEAT_SHUTDOWN CheatShutdown(void);

    // Menu operations
    CHEAT_API void CheatShowMenu(void);
    CHEAT_API void CheatHideMenu(void);
    CHEAT_API void CheatToggleMenu(void);
    CHEAT_API bool CheatIsMenuVisible(void);

    // ESP operations
    CHEAT_API void CheatShowESP(void);
    CHEAT_API void CheatHideESP(void);
    CHEAT_API void CheatToggleESP(void);
    CHEAT_API bool CheatIsESPEnabled(void);

    // Aimbot operations
    CHEAT_API void CheatEnableAimbot(void);
    CHEAT_API void CheatDisableAimbot(void);
    CHEAT_API void CheatToggleAimbot(void);
    CHEAT_API bool CheatIsAimbotEnabled(void);

    // Player management
    CHEAT_API void CheatAddPlayer(PlayerInfo* player);
    CHEAT_API void CheatRemovePlayer(const char* name);
    CHEAT_API size_t CheatGetPlayerCount(void);
    CHEAT_API PlayerInfo* CheatGetPlayer(size_t index);

    // Legend settings
    CHEAT_API void CheatAddLegendSettings(LegendSettings* settings);
    CHEAT_API LegendSettings* CheatGetLegendSettings(const char* legend_name);
    CHEAT_API void CheatUpdateLegendSettings(const char* legend_name, LegendSettings* settings);

    // Triggerbot configuration
    CHEAT_API void CheatSetTriggerbotConfig(TriggerbotConfig* config);
    CHEAT_API TriggerbotConfig* CheatGetTriggerbotConfig(void);

    // Rendering
    CHEAT_API void CheatRenderFrame(ID3D11DeviceContext* ctx);
    CHEAT_API void CheatPresentFrame(bool vsync);

    // Hotkey registration
    CHEAT_API bool CheatRegisterHotkeys(void);
    CHEAT_API void CheatUnregisterHotkeys(void);

    // Triggerbot humanization
    CHEAT_API int CheatGetReactionDelay(void);
    CHEAT_API float CheatGetMicroJitter(void);
}

// ============================================================================
// CONFIGURATION DEFAULTS
// ============================================================================

#define DEFAULT_WINDOW_WIDTH     600
#define DEFAULT_WINDOW_HEIGHT    450
#define DEFAULT_WINDOW_X         100
#define DEFAULT_WINDOW_Y         100
#define DEFAULT_MENU_HOTKEY      0x90  // INSERT
#define DEFAULT_ESP_HOTKEY       0x24  // HOME

// Legend defaults (Wraith tight, Gibraltar loose)
#define DEFAULT_WITCH_FOV        6.0f    // Tight FOV for Wraith
#define DEFAULT_GIBBS_FOV        12.0f   // Looser FOV for Gibraltar
#define DEFAULT_WITCH_SMOOTH     0.85f   // High smoothing for Wraith
#define DEFAULT_GIBBS_SMOOTH     0.65f   // Medium smoothing for Gibraltar

// Triggerbot humanization defaults
#define DEFAULT_MIN_REACTION     50      // Minimum reaction time (ms)
#define DEFAULT_MAX_REACTION     150     // Maximum reaction time (ms)
#define DEFAULT_MICRO_JITTER     1.5f    // Micro-jitter std deviation (degrees)

// ============================================================================
// END OF HEADER
// ============================================================================

#endif // __APEX_CHEAT_H__
