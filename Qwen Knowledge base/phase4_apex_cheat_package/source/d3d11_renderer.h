/**
 * D3D11 Renderer for Apex Cheat - Chudvision/Ignite/Kernaim Style
 *
 * Internal overlay rendering directly onto Apex's DirectX pipeline
 * Features: Menu, ESP, Triggerbot Humanization, Legend-Adaptive Aimbot
 */

#pragma once

#ifndef __D3D11_RENDERER_H__
#define __D3D11_RENDERER_H__

#include <d3d11.h>
#include <dxgi.h>
#include <stdint.h>
#include <string>
#include <vector>
#include <map>
#include <xmmintrin.h>
#include <DirectXMath.h>

// Forward declarations (only if not already defined in apex_cheat.h)
#ifndef __APEX_CHEAT_H__
struct PlayerInfo;
struct LegendSettings;
struct TriggerbotConfig;
#endif

using namespace DirectX;

// ============================================================================
// D3D11 RENDERER CONFIGURATION
// ============================================================================

typedef struct _D3D11Config {
    bool enable_vsync;
    bool transparent_background;
    bool always_on_top;
    uint32_t width;
    uint32_t height;
} D3D11Config;

// ============================================================================
// D3D11 RENDERER CONTEXT
// ============================================================================

typedef struct _D3D11Context {
    // DirectX components
    ID3D11Device* pDevice;
    ID3D11DeviceContext* pContext;
    IDXGISwapChain* pSwapChain;
    ID3D11Texture2D* pBackBuffer;
    ID3D11RenderTargetView* pRenderTargetView;

    // Menu state
    bool menu_visible;
    bool esp_enabled;
    bool aimbot_enabled;

    // Player list for ESP
    std::vector<PlayerInfo> players;
    std::vector<bool> player_visible;

    // Legend settings (for adaptive aimbot)
    std::map<std::string, LegendSettings> legend_settings;

    // Triggerbot configuration with humanization
    TriggerbotConfig triggerbot_config;

    // Rendering state
    uint32_t frame_count;
    float last_frame_time;
    float menu_alpha;           // Menu transparency (0.0-1.0)
} D3D11Context;

// ============================================================================
// FUNCTION PROTOTYPES
// ============================================================================

/**
 * Initialize D3D11 renderer with configuration
 */
bool D3D11_Init(D3D11Context* ctx, const D3D11Config* config);

/**
 * Shutdown D3D11 renderer and release resources
 */
void D3D11_Shutdown(D3D11Context* ctx);

/**
 * Create render target for menu/ESP rendering
 */
bool D3D11_CreateRenderTarget(D3D11Context* ctx);

/**
 * Render menu overlay (ImGui-style)
 */
void D3D11_RenderMenu(D3D11Context* ctx, ID3D11DeviceContext* device_ctx);

/**
 * Render ESP overlay for players
 */
void D3D11_RenderESP(D3D11Context* ctx, ID3D11DeviceContext* device_ctx);

/**
 * Render single player ESP with legend-specific styling
 */
void D3D11_RenderPlayerESP(D3D11Context* ctx, ID3D11DeviceContext* device_ctx,
                           size_t player_index);

/**
 * Render aimbot indicators (FOV circle, aim spot)
 */
void D3D11_RenderAimbot(D3D11Context* ctx, ID3D11DeviceContext* device_ctx);

/**
 * Present frame to screen
 */
void D3D11_Present(D3D11Context* ctx, bool vsync);

/**
 * Toggle menu visibility
 */
void D3D11_ToggleMenu(D3D11Context* ctx);

/**
 * Toggle ESP visibility
 */
void D3D11_ToggleESP(D3D11Context* ctx);

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Convert color to D3D11 format (RGBA)
 */
inline XMFLOAT4 D3D11_MakeColor(uint8_t r, uint8_t g, uint8_t b, uint8_t a = 255) {
    return XMFLOAT4{
        static_cast<float>(r) / 255.0f,
        static_cast<float>(g) / 255.0f,
        static_cast<float>(b) / 255.0f,
        static_cast<float>(a) / 255.0f
    };
}

/**
 * Draw filled rectangle
 */
void D3D11_DrawRect(D3D11Context* ctx, ID3D11DeviceContext* device_ctx,
                    float x, float y, float width, float height,
                    XMFLOAT4 color);

/**
 * Draw outlined rectangle
 */
void D3D11_DrawRectOutline(D3D11Context* ctx, ID3D11DeviceContext* device_ctx,
                           float x, float y, float width, float height,
                           XMFLOAT4 color, float thickness = 1.0f);

/**
 * Draw text (simplified - would use sprite font in full implementation)
 */
void D3D11_DrawText(D3D11Context* ctx, ID3D11DeviceContext* device_ctx,
                    const char* text, float x, float y, XMFLOAT4 color,
                    float size = 16.0f);

/**
 * Draw circle (for FOV indicators)
 */
void D3D11_DrawCircle(D3D11Context* ctx, ID3D11DeviceContext* device_ctx,
                      float center_x, float center_y, float radius,
                      XMFLOAT4 color, float thickness = 1.0f);

/**
 * Get legend-specific settings for aimbot
 */
LegendSettings D3D11_GetLegendSettings(D3D11Context* ctx, const char* legend_name);

// ============================================================================
// END OF HEADER
// ============================================================================

#endif // __D3D11_RENDERER_H__
