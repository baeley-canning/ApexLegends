/**
 * D3D11 Renderer Implementation for Apex Cheat - Chudvision/Ignite/Kernaim Style
 *
 * Internal overlay rendering directly onto Apex's DirectX pipeline
 * Features: Menu, ESP, Triggerbot Humanization, Legend-Adaptive Aimbot
 */

#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi.h>
#include <DirectXMath.h>
#include <Windows.h>
#include <string>
#include <vector>
#include <map>
#include <random>

#include "apex_cheat.h"
#include "d3d11_renderer.h"

using namespace DirectX;

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

    return SUCCEEDED(ctx->pDevice->CreateBuffer(
        &bd, &initData, pBuffer
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

    hr = ctx->pDevice->CreateVertexShader(
        pBlob->GetBufferPointer(),
        pBlob->GetBufferSize(),
        nullptr,
        pShader
    );

    if (pBlob) {
        pBlob->Release();
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

    hr = ctx->pDevice->CreatePixelShader(
        pBlob->GetBufferPointer(),
        pBlob->GetBufferSize(),
        nullptr,
        pShader
    );

    if (pBlob) {
        pBlob->Release();
    }

    return SUCCEEDED(hr);
}

// ============================================================================
// D3D11 INITIALIZATION
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
    sd.BufferDesc.RefreshRate.Numerator = 144;
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
        pFactory->Release();
        return false;
    }

    // Initialize context state
    ctx->menu_visible = true;
    ctx->esp_enabled = true;
    ctx->aimbot_enabled = true;
    ctx->frame_count = 0;
    ctx->last_frame_time = 0.0f;
    ctx->menu_alpha = 0.85f; // 85% opacity

    // Initialize default legend settings (Wraith tight, Gibraltar loose)
    LegendSettings wraith_settings = {};
    wraith_settings.legend_name = "Wraith";
    wraith_settings.fov_degrees = DEFAULT_WITCH_FOV;
    wraith_settings.smoothing = DEFAULT_WITCH_SMOOTH;
    wraith_settings.bone_priority = 0; // Head
    wraith_settings.recoil_reduction = 0.7f;
    wraith_settings.prediction_factor = 0.8f;

    LegendSettings gibbs_settings = {};
    gibbs_settings.legend_name = "Gibraltar";
    gibbs_settings.fov_degrees = DEFAULT_GIBBS_FOV;
    gibbs_settings.smoothing = DEFAULT_GIBBS_SMOOTH;
    gibbs_settings.bone_priority = 2; // Chest
    gibbs_settings.recoil_reduction = 0.5f;
    gibbs_settings.prediction_factor = 0.6f;

    LegendSettings lifeline_settings = {};
    lifeline_settings.legend_name = "Lifeline";
    lifeline_settings.fov_degrees = 9.0f; // Balanced
    lifeline_settings.smoothing = 0.75f;  // Balanced
    lifeline_settings.bone_priority = 1;  // Neck
    lifeline_settings.recoil_reduction = 0.6f;
    lifeline_settings.prediction_factor = 0.7f;

    ctx->legend_settings["Wraith"] = wraith_settings;
    ctx->legend_settings["Gibraltar"] = gibbs_settings;
    ctx->legend_settings["Lifeline"] = lifeline_settings;

    // Initialize triggerbot configuration with humanization
    ctx->triggerbot_config.enabled = true;
    ctx->triggerbot_config.base_reaction_ms = 100;  // Midpoint of 50-150ms
    ctx->triggerbot_config.min_reaction_ms = DEFAULT_MIN_REACTION;
    ctx->triggerbot_config.max_reaction_ms = DEFAULT_MAX_REACTION;
    ctx->triggerbot_config.weapon_delay_multiplier = 1.0f;
    ctx->triggerbot_config.micro_jitter_std = DEFAULT_MICRO_JITTER;
    ctx->triggerbot_config.hold_fire_until_acquired = true;

    g_Initialized = true;

    pFactory->Release();
    return true;
}

void D3D11_Shutdown(D3D11Context* ctx) {
    if (!ctx) {
        return;
    }

    // Release render target view
    if (ctx->pRenderTargetView) {
        ctx->pRenderTargetView->Release();
        ctx->pRenderTargetView = nullptr;
    }

    // Release back buffer
    if (ctx->pBackBuffer) {
        ctx->pBackBuffer->Release();
        ctx->pBackBuffer = nullptr;
    }

    // Release device context
    if (ctx->pContext) {
        ctx->pContext->Release();
        ctx->pContext = nullptr;
    }

    // Release device
    if (ctx->pDevice) {
        ctx->pDevice->Release();
        ctx->pDevice = nullptr;
    }

    // Release swap chain
    if (ctx->pSwapChain) {
        ctx->pSwapChain->Release();
        ctx->pSwapChain = nullptr;
    }

    g_Initialized = false;
}

bool D3D11_CreateRenderTarget(D3D11Context* ctx) {
    if (!ctx || !ctx->pSwapChain) {
        return false;
    }

    // Get back buffer
    HRESULT hr = ctx->pSwapChain->GetBuffer(
        0,
        __uuidof(ID3D11Texture2D),
        (void**)&ctx->pBackBuffer
    );

    if (FAILED(hr)) {
        return false;
    }

    // Create render target view
    hr = ctx->pDevice->CreateRenderTargetView(
        ctx->pBackBuffer,
        nullptr,
        &ctx->pRenderTargetView
    );

    return SUCCEEDED(hr);
}

// ============================================================================
// D3D11 RENDERING - MENU
// ============================================================================

void D3D11_RenderMenu(D3D11Context* ctx, ID3D11DeviceContext* device_ctx) {
    if (!ctx || !device_ctx || !ctx->menu_visible) {
        return;
    }

    // Clear background with transparency
    XMFLOAT4 bg_color = D3D11_MakeColor(26, 26, 46, (uint8_t)(200 * ctx->menu_alpha));
    device_ctx->ClearRenderTargetView(
        ctx->pRenderTargetView,
        &bg_color.x
    );

    // Draw menu title
    D3D11_DrawText(ctx, device_ctx, "APEX CHEAT MENU", 20, 20,
                   D3D11_MakeColor(0, 255, 127), 24.0f);

    // Draw version
    char version_str[32];
    snprintf(version_str, sizeof(version_str), "v%d.%d.%d", 
             CHEAT_VERSION_MAJOR, CHEAT_VERSION_MINOR, CHEAT_VERSION_BUILD);
    D3D11_DrawText(ctx, device_ctx, version_str, 450, 25,
                   D3D11_MakeColor(150, 150, 150), 14.0f);

    // Draw menu items
    float y_offset = 60;

    // ESP toggle
    D3D11_DrawRectOutline(ctx, device_ctx, 20, y_offset, 150, 30,
                          ctx->esp_enabled ? D3D11_MakeColor(0, 255, 127) : D3D11_MakeColor(100, 100, 100));
    D3D11_DrawText(ctx, device_ctx, ctx->esp_enabled ? "ESP: ON" : "ESP: OFF",
                   30, y_offset + 8, D3D11_MakeColor(255, 255, 255));

    // Aim toggle
    y_offset += 45;
    D3D11_DrawRectOutline(ctx, device_ctx, 20, y_offset, 150, 30,
                          ctx->aimbot_enabled ? D3D11_MakeColor(0, 255, 127) : D3D11_MakeColor(100, 100, 100));
    D3D11_DrawText(ctx, device_ctx, ctx->aimbot_enabled ? "AIM: ON" : "AIM: OFF",
                   30, y_offset + 8, D3D11_MakeColor(255, 255, 255));

    // Triggerbot humanization indicator
    y_offset += 45;
    D3D11_DrawRectOutline(ctx, device_ctx, 20, y_offset, 150, 30,
                          D3D11_MakeColor(255, 215, 0)); // Gold for humanization
    D3D11_DrawText(ctx, device_ctx, "HUMANIZER: ON",
                   30, y_offset + 8, D3D11_MakeColor(255, 215, 0));

    // Frame counter
    y_offset += 50;
    char frame_str[64];
    snprintf(frame_str, sizeof(frame_str), "Frame: %u | FPS: %.1f",
             ctx->frame_count, 1000.0f / ctx->last_frame_time);
    D3D11_DrawText(ctx, device_ctx, frame_str, 20, y_offset,
                   D3D11_MakeColor(150, 150, 150), 14.0f);

    // Legend settings summary
    y_offset += 25;
    D3D11_DrawText(ctx, device_ctx, "Legend Settings:", 20, y_offset,
                   D3D11_MakeColor(180, 180, 180), 12.0f);

    // Wraith settings
    auto wraith_it = ctx->legend_settings.find("Wraith");
    if (wraith_it != ctx->legend_settings.end()) {
        char wraith_str[64];
        snprintf(wraith_str, sizeof(wraith_str), "Wraith: FOV=%.1f, Smooth=%.2f",
                 wraith_it->second.fov_degrees, wraith_it->second.smoothing);
        D3D11_DrawText(ctx, device_ctx, wraith_str, 20, y_offset + 15,
                       D3D11_MakeColor(0, 255, 255), 11.0f);
    }

    // Gibraltar settings
    auto gibbs_it = ctx->legend_settings.find("Gibraltar");
    if (gibbs_it != ctx->legend_settings.end()) {
        char gibbs_str[64];
        snprintf(gibbs_str, sizeof(gibbs_str), "Gibraltar: FOV=%.1f, Smooth=%.2f",
                 gibbs_it->second.fov_degrees, gibbs_it->second.smoothing);
        D3D11_DrawText(ctx, device_ctx, gibbs_str, 20, y_offset + 30,
                       D3D11_MakeColor(180, 140, 50), 11.0f);
    }
}

// ============================================================================
// D3D11 RENDERING - ESP
// ============================================================================

void D3D11_RenderESP(D3D11Context* ctx, ID3D11DeviceContext* device_ctx) {
    if (!ctx || !device_ctx || !ctx->esp_enabled) {
        return;
    }

    // Render each player
    for (size_t i = 0; i < ctx->players.size(); ++i) {
        D3D11_RenderPlayerESP(ctx, device_ctx, i);
    }
}

void D3D11_RenderPlayerESP(D3D11Context* ctx, ID3D11DeviceContext* device_ctx,
                           size_t player_index) {
    if (player_index >= ctx->players.size()) {
        return;
    }

    const PlayerInfo& player = ctx->players[player_index];

    // Calculate screen position (simplified - would use view matrix in full impl)
    float screen_x = 400.0f + (player_index * 100.0f);
    float screen_y = 300.0f;

    // Get legend-specific color
    XMFLOAT4 box_color = D3D11_MakeColor(0, 255, 0); // Default green for enemies
    if (!player.is_enemy) {
        box_color = D3D11_MakeColor(0, 100, 255); // Blue for allies
    }

    // Adjust color based on legend
    if (player.legend == "Wraith") {
        box_color = D3D11_MakeColor(100, 100, 255); // Purple-ish for Wraith
    } else if (player.legend == "Gibraltar") {
        box_color = D3D11_MakeColor(180, 140, 50); // Gold for Gibraltar
    }

    // Draw box around player
    float box_size = 50.0f + (20.0f / (player.distance + 1)); // Size based on distance
    D3D11_DrawRectOutline(ctx, device_ctx, screen_x - box_size/2, screen_y - box_size,
                          box_size, box_size * 1.8f, box_color);

    // Draw name
    D3D11_DrawText(ctx, device_ctx, player.name.c_str(), screen_x, screen_y - box_size - 20,
                   D3D11_MakeColor(255, 255, 255), 14.0f);

    // Draw legend
    char legend_str[64];
    snprintf(legend_str, sizeof(legend_str), "%s", player.legend.c_str());
    D3D11_DrawText(ctx, device_ctx, legend_str, screen_x, screen_y - box_size - 35,
                   D3D11_MakeColor(200, 200, 200), 11.0f);

    // Draw health bar
    float health_pct = (float)player.health / (float)player.max_health;
    float shield_pct = player.max_shield > 0 ? (float)player.shield / (float)player.max_shield : 0.0f;

    // Shield bar (top)
    D3D11_DrawRect(ctx, device_ctx, screen_x - box_size/2 - 5, screen_y - box_size,
                   box_size + 10, 8, D3D11_MakeColor(0, 255, 255)); // Cyan for shield

    // Health bar (bottom)
    D3D11_DrawRect(ctx, device_ctx, screen_x - box_size/2 - 5, screen_y - box_size + 12,
                   box_size + 10, 8, D3D11_MakeColor(255, 0, 0)); // Red base

    // Draw filled health portion
    D3D11_DrawRect(ctx, device_ctx, screen_x - box_size/2 - 5, screen_y - box_size + 12,
                   (box_size + 10) * health_pct, 8, D3D11_MakeColor(0, 255, 0)); // Green filled

    // Draw distance
    char dist_str[16];
    snprintf(dist_str, sizeof(dist_str), "%.0fm", player.distance);
    D3D11_DrawText(ctx, device_ctx, dist_str, screen_x + box_size/2 + 10, screen_y,
                   D3D11_MakeColor(255, 255, 255), 12.0f);
}

// ============================================================================
// D3D11 RENDERING - AIMBOT
// ============================================================================

void D3D11_RenderAimbot(D3D11Context* ctx, ID3D11DeviceContext* device_ctx) {
    if (!ctx || !device_ctx || !ctx->aimbot_enabled) {
        return;
    }

    // Get center of screen (aim spot)
    float screen_center_x = 960.0f; // 1920/2
    float screen_center_y = 540.0f; // 1080/2

    // Draw crosshair at center
    D3D11_DrawRect(ctx, device_ctx, screen_center_x - 8, screen_center_y, 16, 2,
                   D3D11_MakeColor(0, 255, 0));
    D3D11_DrawRect(ctx, device_ctx, screen_center_x, screen_center_y - 8, 2, 16,
                   D3D11_MakeColor(0, 255, 0));

    // Draw FOV circle (legend-specific)
    auto default_settings = D3D11_GetLegendSettings(ctx, "Wraith"); // Default to Wraith
    float fov_radius = screen_center_y * tanf(default_settings.fov_degrees * 3.14159f / 180.0f / 2.0f);

    D3D11_DrawCircle(ctx, device_ctx, screen_center_x, screen_center_y, fov_radius,
                     D3D11_MakeColor(0, 255, 0, 100), 1.0f);

    // Draw aim spot indicator
    D3D11_DrawRectOutline(ctx, device_ctx, screen_center_x - 5, screen_center_y - 5,
                          10, 10, D3D11_MakeColor(255, 215, 0, 200));

    // Draw reaction time indicator (triggerbot humanization)
    char reaction_str[64];
    int reaction_delay = ctx->triggerbot_config.base_reaction_ms;
    snprintf(reaction_str, sizeof(reaction_str), "Reaction: %dms", reaction_delay);
    D3D11_DrawText(ctx, device_ctx, reaction_str, screen_center_x + 20, screen_center_y - 60,
                   D3D11_MakeColor(255, 215, 0), 12.0f);
}

// ============================================================================
// D3D11 PRESENT
// ============================================================================

void D3D11_Present(D3D11Context* ctx, bool vsync) {
    if (!ctx || !ctx->pSwapChain) {
        return;
    }

    ctx->pSwapChain->Present(vsync ? 1 : 0, 0);
    ctx->frame_count++;
}

// ============================================================================
// D3D11 TOGGLE FUNCTIONS
// ============================================================================

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
    // Simplified rectangle rendering using multiple small rects
    const float step = 2.0f;
    for (float ry = y; ry < y + height; ry += step) {
        for (float rx = x; rx < x + width; rx += step) {
            // Draw individual pixel/rect
            D3D11_DrawRectOutline(ctx, device_ctx, rx, ry, step, step, color, 1.0f);
        }
    }
}

void D3D11_DrawRectOutline(D3D11Context* ctx, ID3D11DeviceContext* device_ctx,
                           float x, float y, float width, float height,
                           XMFLOAT4 color, float thickness) {
    // Top line
    D3D11_DrawRect(ctx, device_ctx, x, y, width, thickness, color);
    // Bottom line
    D3D11_DrawRect(ctx, device_ctx, x, y + height - thickness, width, thickness, color);
    // Left line
    D3D11_DrawRect(ctx, device_ctx, x, y, thickness, height, color);
    // Right line
    D3D11_DrawRect(ctx, device_ctx, x + width - thickness, y, thickness, height, color);
}

void D3D11_DrawText(D3D11Context* ctx, ID3D11DeviceContext* device_ctx,
                    const char* text, float x, float y, XMFLOAT4 color,
                    float size) {
    // Simplified text rendering - draw character boxes
    for (const char* p = text; *p; ++p) {
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
        } else if (*p == ':') {
            // Colon
            D3D11_DrawRect(ctx, device_ctx, char_x, y + size * 0.2f,
                           size * 0.6f, 2.0f, color);
            D3D11_DrawRect(ctx, device_ctx, char_x, y + size - size * 0.2f,
                           size * 0.6f, 2.0f, color);
        }
    }
}

void D3D11_DrawCircle(D3D11Context* ctx, ID3D11DeviceContext* device_ctx,
                      float center_x, float center_y, float radius,
                      XMFLOAT4 color, float thickness) {
    // Simplified circle - draw multiple rectangles around circumference
    const int segments = 36;
    const float angle_step = 2.0f * 3.14159f / (float)segments;

    for (int i = 0; i < segments; ++i) {
        float angle1 = i * angle_step;
        float angle2 = (i + 1) * angle_step;

        float x1 = center_x + cosf(angle1) * radius;
        float y1 = center_y + sinf(angle1) * radius;
        float x2 = center_x + cosf(angle2) * radius;
        float y2 = center_y + sinf(angle2) * radius;

        // Draw segment as rectangle
        D3D11_DrawRectOutline(ctx, device_ctx, x1 - thickness, y1 - thickness,
                              x2 - x1 + thickness * 2, y2 - y1 + thickness * 2,
                              color, thickness);
    }
}

LegendSettings D3D11_GetLegendSettings(D3D11Context* ctx, const char* legend_name) {
    auto it = ctx->legend_settings.find(legend_name);
    if (it != ctx->legend_settings.end()) {
        return it->second;
    }

    // Return default settings if legend not found
    LegendSettings default_settings = {};
    default_settings.fov_degrees = 9.0f;
    default_settings.smoothing = 0.75f;
    default_settings.bone_priority = 1;
    default_settings.recoil_reduction = 0.6f;
    default_settings.prediction_factor = 0.7f;
    return default_settings;
}

// ============================================================================
// END OF FILE
// ============================================================================
