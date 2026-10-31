/**
 * Apex Cheat Phase 5 - Internal ImGui Overlay
 * 
 * Hybrid Python + C++ DLL architecture with D3D11 rendering
 * Pattern: Kernaim/Ignite/Chudvision style internal overlay
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
#else
    #define CHEAT_API __declspec(dllimport)
#endif

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

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

typedef struct _PlayerInfo {
    std::string name;
    float x, y, z;
    int health;
    int max_health;
    int shield;
    int max_shield;
    std::string legend;
    std::string weapon;
    bool is_enemy;
    bool is_knocked;
} PlayerInfo;

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
    CHEAT_API void CHEAT_API CheatShowMenu(void);
    CHEAT_API void CHEAT_API CheatHideMenu(void);
    CHEAT_API void CHEAT_API CheatToggleMenu(void);
    CHEAT_API bool CHEAT_API CheatIsMenuVisible(void);
    
    // ESP operations
    CHEAT_API void CHEAT_API CheatShowESP(void);
    CHEAT_API void CHEAT_API CheatHideESP(void);
    CHEAT_API void CHEAT_API CheatToggleESP(void);
    CHEAT_API bool CHEAT_API CheatIsESPEnabled(void);
    
    // Player management
    CHEAT_API void CHEAT_API CheatAddPlayer(PlayerInfo* player);
    CHEAT_API void CHEAT_API CheatRemovePlayer(const char* name);
    CHEAT_API size_t CHEAT_API CheatGetPlayerCount(void);
    CHEAT_API PlayerInfo* CHEAT_API CheatGetPlayer(size_t index);
    
    // Rendering
    CHEAT_API void CHEAT_API CheatRenderFrame(ID3D11DeviceContext* ctx);
    
    // Hotkey registration
    CHEAT_API bool CHEAT_API CheatRegisterHotkeys(void);
    CHEAT_API void CHEAT_API CheatUnregisterHotkeys(void);
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

// ============================================================================
// END OF HEADER
// ============================================================================

#endif // __APEX_CHEAT_H__
