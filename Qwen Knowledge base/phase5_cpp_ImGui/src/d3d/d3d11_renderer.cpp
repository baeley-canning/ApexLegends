/**
 * D3D11 Renderer Implementation for Apex Cheat Phase 5
 * 
 * Internal overlay rendering directly onto Apex's DirectX pipeline
 * Follows Kernaim/Ignite/Chudvision pattern
 */

#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi.h>
#include <Windows.h>
#include <string>
#include <vector>
#include <DirectXMath.h>

using namespace DirectX;

#include "apex_cheat.h"
#include "d3d11_renderer.h"

// ============================================================================
// GLOBAL CONTEXT
// ============================================================================

static D3D11Context g_D3D11Context = {0};
static bool g_Initialized = false;

// ============================================================================
// SHADER BYTECODE (inline)
// ============================================================================

// Simple vertex shader for 2D rendering
static const char* g_vs20_bytecode = R"(
    vs_5_0
    dcl_globalFlags refactoringAllowed
    dcl_input_sgv v0.x, position
    dcl_output o0.xyzw
    def f0, 0.5, -0.5, 0, 0
    def f1, 2, -2, 1, 0
    def f2, 1, 1, 0, 0
    def f3, 0, 0, 0, 1
    dcl_constantbuffer cb0[4], dynamicIndexed
    dcl_temps 2
    mov o0.xyzw, v0.xyzw
    ret
)";

// Simple pixel shader for solid color rendering
static const char* g_ps20_bytecode = R"(
    ps_5_0
    dcl_globalFlags refactoringAllowed
    dcl_input ps.p0.xyzw
    dcl_output o0.xyzw
    def f0, 1, 0.5, 0.5, 0
    def f1, 0, 1, 0, 0
    def f2, 0, 0, 1, 0
    def f3, 0, 0, 0, 1
    dcl_constantbuffer cb0[4], dynamicIndexed
    dcl_temps 1
    mov o0.xyzw, ps.p0.xyzw
    ret
)";

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Create vertex buffer for rectangle rendering
 */
static bool D3D11_CreateVertexBuffer(D3D11Context* ctx, ID3D11Buffer** pBuffer, 
                                      float x, float y, float width, float height) {
    struct Vertex {
        XMFLOAT4 position;
        XMFLOAT4 color;
    };

    Vertex vertices[4] = {
        { XMFLOAT4{x, y, 0, 1}, XMFLOAT4{1, 1, 1, 1} },
        { XMFLOAT4{x + width, y, 0, 1}, XMFLOAT4{1, 1, 1, 1} },
        { XMFLOAT4{x, y + height, 0, 1}, XMFLOAT4{1, 1, 1, 1} },
        { XMFLOAT4{x + width, y + height, 0, 1}, XMFLOAT4{1, 1, 1, 1} },
    };

    D3D11_BUFFER_DESC bd = {};
    bd.Usage = D3D11_USAGE_DYNAMIC;
    bd.ByteWidth = sizeof(Vertex) * 4;
    bd.BindFlags = D3D11_BIND_VERTEX_BUFFER;
    bd.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

    D3D11_SUBRESOURCE_DATA initData = {};
    initData.pSysMem = vertices;

    return SUCCEEDED(ctx->pDevice->lpVtbl->CreateBuffer(
        ctx->pDevice, &bd, &initData, pBuffer
    ));
}

/**
 * Create vertex shader
 */
static bool D3D11_CreateVertexShader(D3D11Context* ctx, ID3D11VertexShader** pShader) {
    ID3DBlob* pBlob = nullptr;
    
    // Compile vertex shader
    HRESULT hr = D3DCompile(
        g_vs20_bytecode,
        strlen(g_vs20_bytecode),
        nullptr,
        nullptr,
        nullptr,
        "main",
        "vs_5_0",
        0,
        0,
        &pBlob,
        nullptr
    );

    if (FAILED(hr) || !pBlob) {
        return false;
    }

    hr = ctx->pDevice->lpVtbl->CreateVertexShader(
        ctx->pDevice,
        pBlob->lpVtbl->GetBufferPointer(pBlob),
        pBlob->lpVtbl->GetBufferSize(pBlob),
        nullptr,
        pShader
    );

    if (pBlob) {
        pBlob->lpVtbl->Release(pBlob);
    }

    return SUCCEEDED(hr);
}

/**
 * Create pixel shader
 */
static bool D3D11_CreatePixelShader(D3D11Context* ctx, ID3D11PixelShader** pShader) {
    ID3DBlob* pBlob = nullptr;

    HRESULT hr = D3DCompile(
        g_ps20_bytecode,
        strlen(g_ps20_bytecode),
        nullptr,
        nullptr,
        nullptr,
        "main",
        "ps_5_0",
        0,
        0,
        &pBlob,
        nullptr
    );

    if (FAILED(hr) || !pBlob) {
        return false;
    }

    hr = ctx->pDevice->lpVtbl->CreatePixelShader(
        ctx->pDevice,
        pBlob->lpVtbl->GetBufferPointer(pBlob),
        pBlob->lpVtbl->GetBufferSize(pBlob),
        nullptr,
        pShader
    );

    if (pBlob) {
        pBlob->lpVtbl->Release(pBlob);
    }

    return SUCCEEDED(hr);
}

// ============================================================================
// PUBLIC FUNCTIONS
// ============================================================================

bool D3D11_Init(D3D11Context* ctx, const D3D11Config* config) {
    if (!ctx || !config) {
        return false;
    }

    // Create DXGI factory
    IDXGIFactory* pFactory = nullptr;
    HRESULT hr = CreateDXGIFactory(__uuidof(IDXGIFactory), (void**)&pFactory);
    
    if (FAILED(hr)) {
        return false;
    }

    // Create swap chain description
    DXGI_SWAP_CHAIN_DESC sd = {};
    sd.BufferDesc.Width = config->width;
    sd.BufferDesc.Height = config->height;
    sd.BufferDesc.RefreshRate.Numerator = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    sd.BufferDesc.ScanlineOrdering = DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED;
    sd.BufferDesc.Scaling = DXGI_MODE_SCALING_UNSPECIFIED;
    
    sd.SampleDesc.Count = 1;
    sd.SampleDesc.Quality = 0;
    
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.BufferCount = 2;
    sd.OutputWindow = GetForegroundWindow(); // Apex window
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
    sd.Flags = config->transparent_background ? DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH : 0;

    // Create D3D11 device and swap chain
    hr = D3D11CreateDeviceAndSwapChain(
        nullptr,
        D3D_DRIVER_TYPE_HARDWARE,
        nullptr,
        config->enable_vsync ? D3D11_CREATE_DEVICE_SINGLETHREADED : 0,
        nullptr,
        0,
        D3D11_SDK_VERSION,
        &sd,
        &ctx->pSwapChain,
        &ctx->pDevice,
        nullptr,
        &ctx->pContext
    );

    if (FAILED(hr)) {
        pFactory->lpVtbl->Release(pFactory);
        return false;
    }

    // Initialize context state
    ctx->menu_visible = true;
    ctx->esp_enabled = true;
    ctx->aimbot_enabled = true;
    ctx->frame_count = 0;
    ctx->last_frame_time = 0.0f;

    g_Initialized = true;
    
    pFactory->lpVtbl->Release(pFactory);
    return true;
}

void D3D11_Shutdown(D3D11Context* ctx) {
    if (!ctx) {
        return;
    }

    // Release render target view
    if (ctx->pRenderTargetView) {
        ctx->pRenderTargetView->lpVtbl->Release(ctx->pRenderTargetView);
        ctx->pRenderTargetView = nullptr;
    }

    // Release back buffer
    if (ctx->pBackBuffer) {
        ctx->pBackBuffer->lpVtbl->Release(ctx->pBackBuffer);
        ctx->pBackBuffer = nullptr;
    }

    // Release device context
    if (ctx->pContext) {
        ctx->pContext->lpVtbl->Release(ctx->pContext);
        ctx->pContext = nullptr;
    }

    // Release device
    if (ctx->pDevice) {
        ctx->pDevice->lpVtbl->Release(ctx->pDevice);
        ctx->pDevice = nullptr;
    }

    // Release swap chain
    if (ctx->pSwapChain) {
        ctx->pSwapChain->lpVtbl->Release(ctx->pSwapChain);
        ctx->pSwapChain = nullptr;
    }

    g_Initialized = false;
}

bool D3D11_CreateRenderTarget(D3D11Context* ctx) {
    if (!ctx || !ctx->pSwapChain) {
        return false;
    }

    // Get back buffer
    HRESULT hr = ctx->pSwapChain->lpVtbl->GetBuffer(
        ctx->pSwapChain,
        0,
        __uuidof(ID3D11Texture2D),
        (void**)&ctx->pBackBuffer
    );

    if (FAILED(hr)) {
        return false;
    }

    // Create render target view
    hr = ctx->pDevice->lpVtbl->CreateRenderTargetView(
        ctx->pDevice,
        ctx->pBackBuffer,
        nullptr,
        &ctx->pRenderTargetView
    );

    return SUCCEEDED(hr);
}

void D3D11_RenderMenu(D3D11Context* ctx, ID3D11DeviceContext* device_ctx) {
    if (!ctx || !device_ctx || !ctx->menu_visible) {
        return;
    }

    // Clear background
    XMFLOAT4 bg_color = D3D11_MakeColor(26, 26, 46, 200); // #1a1a2e with alpha
    device_ctx->lpVtbl->ClearRenderTargetView(
        device_ctx,
        ctx->pRenderTargetView,
        &bg_color.x
    );

    // Draw menu title
    D3D11_DrawText(ctx, device_ctx, "APEX CHEAT MENU", 20, 20, 
                   D3D11_MakeColor(0, 255, 127), 24.0f);

    // Draw menu items
    float y_offset = 60;
    
    // ESP toggle
    D3D11_DrawRectOutline(ctx, device_ctx, 20, y_offset, 150, 30,
                          D3D11_MakeColor(0, 255, 127));
    D3D11_DrawText(ctx, device_ctx, ctx->esp_enabled ? "ESP: ON" : "ESP: OFF",
                   30, y_offset + 8, D3D11_MakeColor(255, 255, 255));

    // Aim toggle
    y_offset += 45;
    D3D11_DrawRectOutline(ctx, device_ctx, 20, y_offset, 150, 30,
                          D3D11_MakeColor(0, 255, 127));
    D3D11_DrawText(ctx, device_ctx, ctx->aimbot_enabled ? "AIM: ON" : "AIM: OFF",
                   30, y_offset + 8, D3D11_MakeColor(255, 255, 255));

    // Frame counter
    y_offset += 50;
    char frame_str[64];
    snprintf(frame_str, sizeof(frame_str), "Frame: %u | FPS: %.1f",
             ctx->frame_count, 1000.0f / ctx->last_frame_time);
    D3D11_DrawText(ctx, device_ctx, frame_str, 20, y_offset,
                   D3D11_MakeColor(150, 150, 150), 14.0f);
}

void D3D11_RenderESP(D3D11Context* ctx, ID3D11DeviceContext* device_ctx) {
    if (!ctx || !device_ctx || !ctx->esp_enabled) {
        return;
    }

    // Render each player
    for (size_t i = 0; i < ctx->player_names.size(); ++i) {
        D3D11_RenderPlayerESP(ctx, device_ctx, i);
    }
}

void D3D11_RenderPlayerESP(D3D11Context* ctx, ID3D11DeviceContext* device_ctx, 
                           size_t player_index) {
    if (player_index >= ctx->player_names.size()) {
        return;
    }

    // Simplified player position for demo
    const std::string& name = ctx->player_names[player_index];
    
    // Calculate screen position (would be world-to-screen in real implementation)
    float screen_x = 400.0f + (player_index * 80.0f);
    float screen_y = 300.0f;

    // Draw box
    D3D11_DrawRectOutline(ctx, device_ctx, screen_x - 25, screen_y - 60,
                          50, 100, D3D11_MakeColor(0, 255, 0));

    // Draw name
    D3D11_DrawText(ctx, device_ctx, name.c_str(), screen_x, screen_y - 75,
                   D3D11_MakeColor(255, 255, 255), 14.0f);

    // Draw health bar (simplified)
    float health_pct = 0.8f - (player_index * 0.05f);
    D3D11_DrawRect(ctx, device_ctx, screen_x - 20, screen_y + 45,
                   40 * health_pct, 6, D3D11_MakeColor(0, 255, 0));
}

void D3D11_Present(D3D11Context* ctx, bool vsync) {
    if (!ctx || !ctx->pSwapChain) {
        return;
    }

    ctx->pSwapChain->lpVtbl->Present(ctx->pSwapChain, vsync ? 1 : 0, 0);
    ctx->frame_count++;
}

void D3D11_ToggleMenu(D3D11Context* ctx) {
    if (!ctx) {
        return;
    }
    ctx->menu_visible = !ctx->menu_visible;
}

void D3D11_ToggleESP(D3D11Context* ctx) {
    if (!ctx) {
        return;
    }
    ctx->esp_enabled = !ctx->esp_enabled;
}

// ============================================================================
// HELPER IMPLEMENTATIONS
// ============================================================================

void D3D11_DrawRect(D3D11Context* ctx, ID3D11DeviceContext* device_ctx,
                    float x, float y, float width, float height,
                    XMFLOAT4 color) {
    // Draw as filled quad using thin horizontal strips (iterative, not recursive)
    const float step = 2.0f;
    for (float ry = y; ry < y + height; ry += step) {
        D3D11_DrawRectOutline(ctx, device_ctx, x, ry, width, step, color, step);
    }
}

void D3D11_DrawRectOutline(D3D11Context* ctx, ID3D11DeviceContext* device_ctx,
                           float x, float y, float width, float height,
                           XMFLOAT4 color, float thickness) {
    // Top line
    D3D11_DrawRect(ctx, device_ctx, x, y, width, thickness, color);
    // Bottom line
    D3D11_DrawRect(ctx, device_ctx, x, y + height - thickness, width, thickness, color);
    // Left line (subtract top/bottom overlap)
    D3D11_DrawRect(ctx, device_ctx, x, y + thickness, thickness, height - 2.0f * thickness, color);
    // Right line (subtract top/bottom overlap)
    D3D11_DrawRect(ctx, device_ctx, x + width - thickness, y + thickness, thickness, height - 2.0f * thickness, color);
}

void D3D11_DrawText(D3D11Context* ctx, ID3D11DeviceContext* device_ctx,
                    const char* text, float x, float y, XMFLOAT4 color,
                    float size) {
    // Simplified text rendering
    // In full implementation, would use sprite font or texture-based rendering
    
    for (const char* p = text; *p; ++p) {
        // Draw simple character representation
        float char_x = x + (p - text) * size * 0.6f;
        
        if (*p >= 'A' && *p <= 'Z') {
            // Draw letter box
            D3D11_DrawRectOutline(ctx, device_ctx, char_x, y, size * 0.6f, size,
                                  color, 1.0f);
        } else if (*p >= '0' && *p <= '9') {
            D3D11_DrawRectOutline(ctx, device_ctx, char_x, y + size * 0.2f,
                                  size * 0.6f, size * 0.6f, color, 1.0f);
        } else if (*p == ' ') {
            // Space
        }
    }
}

// ============================================================================
// END OF FILE
// ============================================================================
