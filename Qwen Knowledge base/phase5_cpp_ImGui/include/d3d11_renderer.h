/**
 * D3D11 Renderer for Apex Cheat Phase 5
 * 
 * Internal overlay rendering directly onto Apex's DirectX pipeline
 * Follows Kernaim/Ignite/Chudvision pattern
 */

#pragma once

#ifndef __D3D11_RENDERER_H__
#define __D3D11_RENDERER_H__

#include <d3d11.h>
#include <DirectXMath.h>
#include <string>
#include <vector>

// ============================================================================
// D3D11 RENDERER CONFIGURATION
// ============================================================================

using namespace DirectX;

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
    IDXGISwapChain* pSwapChain;
    ID3D11Device* pDevice;
    ID3D11DeviceContext* pContext;
    ID3D11Texture2D* pBackBuffer;
    ID3D11RenderTargetView* pRenderTargetView;
    
    // Menu state
    bool menu_visible;
    bool esp_enabled;
    bool aimbot_enabled;
    
    // Player list for ESP
    std::vector<std::string> player_names;
    std::vector<bool> player_visible;
    
    // Rendering state
    uint32_t frame_count;
    float last_frame_time;
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
 * Render menu overlay
 */
void D3D11_RenderMenu(D3D11Context* ctx, ID3D11DeviceContext* device_ctx);

/**
 * Render ESP overlay for players
 */
void D3D11_RenderESP(D3D11Context* ctx, ID3D11DeviceContext* device_ctx);

/**
 * Render single player ESP
 */
void D3D11_RenderPlayerESP(D3D11Context* ctx, ID3D11DeviceContext* device_ctx, 
                           size_t player_index);

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
 * Draw text
 */
void D3D11_DrawText(D3D11Context* ctx, ID3D11DeviceContext* device_ctx,
                    const char* text, float x, float y, XMFLOAT4 color,
                    float size = 16.0f);

// ============================================================================
// END OF HEADER
// ============================================================================

#endif // __D3D11_RENDERER_H__
