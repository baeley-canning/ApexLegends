#include "esp_renderer.hpp"
#include "entity_extractor.hpp"
#include <d3dcompiler.h>
#include <cmath>
#include <sstream>
#include <iomanip>

// ============================================================================
// ESP Renderer Implementation
// ============================================================================

// ---------------------------------------------------------------------------
//  Static overlay window creation helpers
// ---------------------------------------------------------------------------

static const wchar_t* kOverlayClassName = L"ApexESPOverlayClass";

// Window procedure for the overlay window — handles transparency and click-through.
static LRESULT CALLBACK OverlayWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_ERASEBKGND:
            return 1;  // Prevent background erase — we draw everything ourselves
        case WM_PAINT: {
            PAINTSTRUCT ps{};
            HDC hdc = BeginPaint(hwnd, &ps);
            
            RECT rc{};
            GetClientRect(hwnd, &rc);
            int w = rc.right - rc.left;
            int h = rc.bottom - rc.top;
            
            // Create a memory DC for double-buffering
            HDC mem_dc = CreateCompatibleDC(hdc);
            HBITMAP bmp = CreateCompatibleBitmap(hdc, w, h);
            HGDIOBJ old_obj = SelectObject(mem_dc, bmp);
            
            // Fill with clear colour (our transparency key)
            static const COLORREF CLEAR_COLOR = RGB(255, 0, 254);
            FillRect(mem_dc, &rc, CreateSolidBrush(CLEAR_COLOR));
            
            BitBlt(hdc, 0, 0, w, h, mem_dc, 0, 0, SRCCOPY);
            
            SelectObject(mem_dc, old_obj);
            DeleteObject(bmp);
            DeleteDC(mem_dc);
            EndPaint(hwnd, &ps);
            return 0;
        }
        case WM_DESTROY:
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
            return 0;
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam);
}

HWND ESPRenderer::CreateOverlayWindow(HWND game_hwnd) {
    if (!game_hwnd) return nullptr;
    
    // Get the game window position and size
    RECT rc{};
    if (!GetWindowRect(game_hwnd, &rc)) return nullptr;
    int width  = rc.right - rc.left;
    int height = rc.bottom - rc.top;
    
    // Register window class (only once)
    WNDCLASSEXW wcex{};
    wcex.cbSize        = sizeof(WNDCLASSEXW);
    wcex.style         = CS_HREDRAW | CS_VREDRAW;
    wcex.lpfnWndProc   = OverlayWndProc;
    wcex.hInstance     = GetModuleHandleW(nullptr);
    wcex.hCursor       = LoadCursorW(nullptr, IDC_ARROW);
    wcex.lpszClassName = kOverlayClassName;
    
    if (!RegisterClassExW(&wcex)) {
        WNDCLASSEXW wc2{};
        wc2.cbSize    = sizeof(WNDCLASSEXW);
        wc2.style     = CS_HREDRAW | CS_VREDRAW;
        wc2.lpfnWndProc = DefWindowProcW;
        wc2.hInstance = GetModuleHandleW(nullptr);
        wc2.lpszClassName = kOverlayClassName;
        RegisterClassExW(&wc2);
    }
    
    // Create a topmost, layered, transparent window that matches the game window size.
    // Key styles:
    //   WS_EX_TOPMOST      — always on top of all windows including fullscreen games
    //   WS_EX_LAYERED      — enables per-pixel alpha / colour-key transparency  
    //   WS_EX_TRANSPARENT  — allows mouse events to pass through (click-through)
    //   WS_EX_TOOLWINDOW   — doesn't appear in taskbar or alt-tab
    HWND overlay = CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW,
        kOverlayClassName,
        L"Apex ESP Overlay",
        WS_POPUP,
        rc.left, rc.top,   // Position matches game window
        width, height,      // Size matches game window
        game_hwnd,          // Owner = game window
        nullptr,
        GetModuleHandleW(nullptr),
        nullptr
    );
    
    if (!overlay) return nullptr;
    
    // Set colour-key transparency: pixels with RGB(255, 0, 254) become transparent.
    SetLayeredWindowAttributes(overlay, RGB(255, 0, 254), 0, LWA_COLORKEY);
    
    // Show the window without activating it (doesn't steal focus from game)
    ShowWindow(overlay, SW_SHOWNOACTIVATE);
    UpdateWindow(overlay);
    
    return overlay;
}

void ESPRenderer::UpdateOverlayPosition() {
    if (!use_overlay_window_ || !overlay_window_) return;
    
    RECT rc{};
    HWND owner = GetAncestor(overlay_window_, GA_OWNER);
    if (owner && GetWindowRect(owner, &rc)) {
        int width  = rc.right - rc.left;
        int height = rc.bottom - rc.top;
        SetWindowPos(overlay_window_, HWND_TOPMOST, 
                     rc.left, rc.top, width, height, SWP_NOACTIVATE);
    } else if (game_hwnd_) {
        // Fallback: use cached game window handle
        if (GetWindowRect(game_hwnd_, &rc)) {
            int width  = rc.right - rc.left;
            int height = rc.bottom - rc.top;
            SetWindowPos(overlay_window_, HWND_TOPMOST, 
                         rc.left, rc.top, width, height, SWP_NOACTIVATE);
        }
    }
}

ESPRenderer::ESPRenderer() {
    // Initialize default bone connections for skeleton rendering
    config_.bone_connections = {
        {0, 1}, {1, 2}, {2, 3}, {3, 4},   // Head to neck
        {1, 5}, {5, 6}, {6, 7},             // Left arm
        {1, 8}, {8, 9}, {9, 10},            // Right arm
        {1, 11}, {11, 12},                    // Torso
        {12, 13}, {13, 14},                   // Left leg
        {12, 15}, {15, 16},                   // Right leg
    };
}

ESPRenderer::~ESPRenderer() {
    Shutdown();
}

bool ESPRenderer::Initialize(HWND game_hwnd) {
    if (!game_hwnd) {
        return false;
    }
    
    // Get window dimensions
    RECT rc{};
    GetWindowRect(game_hwnd, &rc);
    screen_width_ = static_cast<uint32_t>(rc.right - rc.left);
    screen_height_ = static_cast<uint32_t>(rc.bottom - rc.top);
    
    // Create an independent overlay window on top of the game window.
    // This is critical for ESP to be visible through walls — we need a separate
    // HWND that sits above the game with proper layered/transparent styles.
    overlay_window_ = CreateOverlayWindow(game_hwnd);
    if (overlay_window_) {
        use_overlay_window_ = true;
        
        // Get the overlay window's dimensions (should match game)
        RECT overlay_rc{};
        if (GetWindowRect(overlay_window_, &overlay_rc)) {
            screen_width_  = static_cast<uint32_t>(overlay_rc.right - overlay_rc.left);
            screen_height_ = static_cast<uint32_t>(overlay_rc.bottom - overlay_rc.top);
        }
    } else {
        // Fallback: render into the game window itself (may not show through walls)
        use_overlay_window_ = false;
    }
    
    // Create DirectX 11 device for overlay rendering
    // Use the overlay window as OutputWindow if available, otherwise fall back to game_hwnd
    HWND render_target_hwnd = use_overlay_window_ ? overlay_window_ : game_hwnd;
    
    DXGI_SWAP_CHAIN_DESC sd{};
    sd.BufferCount       = 2;
    sd.BufferDesc.Width  = screen_width_;
    sd.BufferDesc.Height = screen_height_;
    sd.BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    sd.BufferDesc.RefreshRate.Numerator = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.BufferUsage       = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow      = render_target_hwnd;
    sd.SampleDesc.Count  = 1;
    sd.SampleDesc.Quality = 0;
    sd.Windowed          = TRUE;
    sd.SwapEffect        = DXGI_SWAP_EFFECT_DISCARD;  // Important: discard mode for performance
    sd.Flags             = DXGI_SWAP_FLAG_ALLOW_MODELESS;  // Allow overlay to work with other windows
    
    // Create D3D11 device
    D3D_FEATURE_LEVEL feature_level;
    HRESULT hr = D3D11CreateDeviceAndSwapChain(
        nullptr, D3D_DRIVER_TYPE_HARDWARE,
        nullptr, D3D11_CREATE_DEVICE_SINGLETHREADED,  // Single-threaded is fine for overlay
        nullptr, 0, D3D11_SDK_VERSION,
        &sd, &swap_chain_,
        &d3d11_device_, &feature_level,
        &d3d11_context_
    );
    
    if (FAILED(hr)) {
        return false;
    }
    
    // Create render target view
    ID3D11Texture2D* back_buffer{};
    hr = swap_chain_->GetBuffer(0, IID_PPV_ARGS(&back_buffer));
    if (SUCCEEDED(hr)) {
        hr = d3d11_device_->CreateRenderTargetView(back_buffer, nullptr, &rtv_);
        back_buffer->Release();
    }
    
    // Set render target
    d3d11_context_->OMSetRenderTargets(1, &rtv_, nullptr);
    
    // Initialize DirectX 12 for advanced features (optional)
    // Chudvision pattern: D3D12 for advanced effects
    hr = D3D12CreateDevice(
        nullptr, D3D_FEATURE_LEVEL_11_0,
        IID_PPV_ARGS(&d3d12_device_)
    );
    
    if (SUCCEEDED(hr)) {
        // Create command queue
        D3D12_COMMAND_QUEUE_DESC cq_desc{};
        cq_desc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
        cq_desc.Flags = D3D12_COMMAND_QUEUE_FLAG_NONE;
        
        hr = d3d12_device_->CreateCommandQueue(&cq_desc,
                                                IID_PPV_ARGS(&command_queue_));
        
        if (SUCCEEDED(hr)) {
            // Create RTV descriptor heap
            D3D12_DESCRIPTOR_HEAP_DESC rtv_heap_desc{};
            rtv_heap_desc.NumDescriptors = 2;
            rtv_heap_desc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
            rtv_heap_desc.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_NONE;
            
            hr = d3d12_device_->CreateDescriptorHeap(&rtv_heap_desc,
                                                      IID_PPV_ARGS(&d3d12_state_.rtv_heap));
            
            if (SUCCEEDED(hr)) {
                d3d12_state_.rtv_handle = 
                    d3d12_state_.rtv_heap->GetCPUDescriptorHandleForHeapStart();
            }
        }
    }
    
    return true;
}

void ESPRenderer::Shutdown() {
    // Clean up overlay window first (so D3D11 doesn't try to present to it)
    if (overlay_window_) {
        ShowWindow(overlay_window_, SW_HIDE);
        DestroyWindow(overlay_window_);
        overlay_window_ = nullptr;
    }
    
    // Release D3D12 resources
    if (d3d12_state_.cmd_list) {
        d3d12_state_.cmd_list->Release();
    }
    if (d3d12_state_.render_target) {
        d3d12_state_.render_target->Release();
    }
    if (d3d12_state_.rtv_heap) {
        d3d12_state_.rtv_heap->Release();
    }
    
    // Release D3D11 resources
    if (d3d11_context_) {
        d3d11_context_->Release();
    }
    if (d3d11_device_) {
        d3d11_device_->Release();
    }
    if (rtv_) {
        rtv_->Release();
    }
    if (back_buffer_) {
        back_buffer_->Release();
    }
    if (swap_chain_) {
        swap_chain_->Release();
    }
    
    // Reset pointers
    d3d12_state_ = {};
    d3d11_context_ = nullptr;
    d3d11_device_ = nullptr;
    rtv_ = nullptr;
    back_buffer_ = nullptr;
    swap_chain_ = nullptr;
}

void ESPRenderer::Render(const std::vector<PlayerEntity>& entities,
                          const EntityExtractor& extractor,
                          const ESPConfig& config) {
    if (!config.enabled || entities.empty()) {
        return;
    }
    
    // Update configuration if changed
    if (config_.update_interval_ms != config.update_interval_ms) {
        UpdateConfig(config);
    }
    
    BeginRender();
    
    for (const auto& player : entities) {
        RenderEntity(player, extractor, config);
    }
    
    EndRender();
}

void ESPRenderer::ToggleFeature(ESPFeature feature, bool enabled) {
    if (enabled) {
        active_features_ |= static_cast<uint32_t>(feature);
    } else {
        active_features_ &= ~static_cast<uint32_t>(feature);
    }
}

void ESPRenderer::UpdateConfig(const ESPConfig& config) {
    config_ = config;

    // Update screen dimensions if needed
    if (config_.screen_width != screen_width_) {
        config_.screen_width = static_cast<uint32_t>(screen_width_);
    }
    if (config_.screen_height != screen_height_) {
        config_.screen_height = static_cast<uint32_t>(screen_height_);
    }
}

void ESPRenderer::BeginRender() {
    if (!d3d11_context_ || !rtv_) {
        return;
    }
    
    // Clear render target with semi-transparent black
    const float clear_color[] = {0.0f, 0.0f, 0.0f, 0.6f};
    d3d11_context_->ClearRenderTargetView(rtv_, clear_color);
    
    // Set blend state for transparency
    D3D11_BLEND_DESC blend_desc{};
    blend_desc.RenderTarget[0].BlendEnable = TRUE;
    blend_desc.RenderTarget[0].SrcBlend = D3D11_BLEND_SRC_ALPHA;
    blend_desc.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC_ALPHA;
    blend_desc.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
    blend_desc.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
    blend_desc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_ZERO;
    blend_desc.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
    blend_desc.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
    
    ID3D11BlendState* blend_state{};
    d3d11_device_->CreateBlendState(&blend_desc, &blend_state);
    d3d11_context_->OMSetBlendState(blend_state, nullptr, 0xFFFFFFFF);
}

void ESPRenderer::EndRender() {
    if (swap_chain_) {
        swap_chain_->Present(1, 0);
    }
    
    // Cleanup blend state
    ID3D11BlendState* blend_state{};
    d3d11_context_->OMGetBlendState(&blend_state, nullptr, nullptr);
    if (blend_state) {
        blend_state->Release();
    }
}

void ESPRenderer::RenderEntity(const PlayerEntity& player,
                                const EntityExtractor& extractor,
                                const ESPConfig& config) {
    // Calculate screen position
    DirectX::XMFLOAT2 screen_pos = CalculateScreenPosition(player.position, config);
    ((PlayerEntity&)player).screen_position = screen_pos;

    // Calculate dimensions based on distance
    float distance_factor = std::max(0.5f,
        1.0f - (player.distance_to_player / 2000.0f));

    ((PlayerEntity&)player).screen_width = 40.0f * distance_factor;
    ((PlayerEntity&)player).screen_height = 90.0f * distance_factor;
    
    // Render each active feature
    if ((active_features_ & static_cast<uint32_t>(ESPFeature::BOX)) != 0) {
        RenderBox(player, config);
    }
    
    if ((active_features_ & static_cast<uint32_t>(ESPFeature::GLOW)) != 0) {
        RenderGlow(player, config);
    }
    
    if ((active_features_ & static_cast<uint32_t>(ESPFeature::SKELETON)) != 0) {
        RenderSkeleton(player, config);
    }
    
    if ((active_features_ & static_cast<uint32_t>(ESPFeature::HEALTH_BAR)) != 0) {
        RenderHealthBar(player, config);
    }
    
    if ((active_features_ & static_cast<uint32_t>(ESPFeature::DISTANCE)) != 0) {
        RenderDistance(player, config);
    }
    
    if ((active_features_ & static_cast<uint32_t>(ESPFeature::SNAPLINES)) != 0) {
        RenderSnapline(player, config);
    }
    
    if ((active_features_ & static_cast<uint32_t>(ESPFeature::NAME)) != 0) {
        RenderName(player, config);
    }
    
    if ((active_features_ & static_cast<uint32_t>(ESPFeature::LEGEND_NAME)) != 0) {
        // Legend name rendering handled with name
    }
    
    if ((active_features_ & static_cast<uint32_t>(ESPFeature::STATE)) != 0) {
        RenderState(player, config);
    }
}

void ESPRenderer::RenderBox(const PlayerEntity& player, const ESPConfig& config) {
    DirectX::XMFLOAT2 pos{
        player.screen_position.x - player.screen_width / 2.0f,
        player.screen_position.y - player.screen_height
    };
    
    DirectX::XMFLOAT2 size{
        player.screen_width + player.screen_width * config.box_padding / 10.0f,
        player.screen_height
    };
    
    // Get team color
    DirectX::XMFLOAT3 color = GetTeamColor(player.team, config.use_glow_colors);
    
    // Adjust alpha based on distance
    float alpha = std::min(1.0f, 1.5f - player.distance_to_player / 1500.0f);
    
    switch (config.box_style) {
        case BoxStyle::OUTLINE:
            DrawRect(pos, size, color, config.line_thickness);
            break;
            
        case BoxStyle::FILLED: {
            // Fill background with team color
            DirectX::XMFLOAT3 fill_color = color;
            fill_color.x *= 0.15f;  // Darker background
            fill_color.y *= 0.15f;
            fill_color.z *= 0.15f;
            FillRect(pos, size, fill_color, alpha * 0.3f);
            
            // Draw outline
            DrawRect(pos, size, color, config.line_thickness);
            break;
        }
        
        case BoxStyle::CORNER: {
            // Kernaim-style corner boxes
            auto corners = CalculateCorners(pos, size, config.corner_size);
            
            for (const auto& [start, end] : corners) {
                DrawLine(start, end, color, config.line_thickness);
            }
            break;
        }
        
        case BoxStyle::ROUNDED: {
            // Simplified rounded boxes using multiple lines
            float radius = config.corner_size;
            
            // Top side
            DrawLine({pos.x + radius, pos.y}, 
                    {pos.x + size.x - radius, pos.y}, color, config.line_thickness);
            // Bottom side
            DrawLine({pos.x + radius, pos.y + size.y},
                    {pos.x + size.x - radius, pos.y + size.y}, color, config.line_thickness);
            // Left side
            DrawLine({pos.x, pos.y + radius},
                    {pos.x, pos.y + size.y - radius}, color, config.line_thickness);
            // Right side
            DrawLine({pos.x + size.x, pos.y + radius},
                    {pos.x + size.x, pos.y + size.y - radius}, color, config.line_thickness);
            break;
        }
        
        case BoxStyle::DASHED: {
            // Dashed outline pattern
            float dash_length = 8.0f;
            float gap_length = 4.0f;
            
            // Top side
            DrawLine({pos.x, pos.y}, {pos.x + size.x, pos.y}, color, config.line_thickness, true);
            // Bottom side
            DrawLine({pos.x, pos.y + size.y}, 
                    {pos.x + size.x, pos.y + size.y}, color, config.line_thickness, true);
            // Left side
            DrawLine({pos.x, pos.y}, {pos.x, pos.y + size.y}, color, config.line_thickness, true);
            // Right side
            DrawLine({pos.x + size.x, pos.y},
                    {pos.x + size.x, pos.y + size.y}, color, config.line_thickness, true);
            break;
        }
    }
}

void ESPRenderer::RenderGlow(const PlayerEntity& player, const ESPConfig& config) {
    if (!config.glow_enabled) {
        return;
    }
    
    DirectX::XMFLOAT2 pos{
        player.screen_position.x - player.screen_width / 2.0f,
        player.screen_position.y - player.screen_height
    };
    
    DirectX::XMFLOAT2 size{
        player.screen_width + player.screen_width * config.box_padding / 10.0f,
        player.screen_height
    };
    
    // Get glow color (brighter version of team color)
    DirectX::XMFLOAT3 glow_color = GetTeamColor(player.team, true);
    
    // Dynamic glow based on distance and health
    float intensity = config.glow_intensity;
    if (config.dynamic_glow) {
        intensity *= std::min(1.5f, 2000.0f / (player.distance_to_player + 1));
        
        // Boost glow for low-health players
        float health_ratio = static_cast<float>(player.health) / 
                            static_cast<float>(player.max_health);
        if (health_ratio < 0.5f) {
            intensity *= 1.3f;
        }
    }
    
    // Draw multiple glow layers (Kernaim-style)
    for (int i = 0; i < 3; ++i) {
        float offset = static_cast<float>(i) * config.glow_thickness;
        DirectX::XMFLOAT2 offset_pos{
            pos.x - offset,
            pos.y - offset
        };
        DirectX::XMFLOAT2 offset_size{
            size.x + offset * 2.0f,
            size.y + offset * 2.0f
        };
        
        // Get outline color with reduced alpha for outer layers
        DirectX::XMFLOAT3 layer_color = glow_color;
        layer_color.x *= intensity;
        layer_color.y *= intensity;
        layer_color.z *= intensity;
        float alpha = std::max(0.1f, 0.4f - i * 0.1f);
        
        DrawRect(offset_pos, offset_size, layer_color, 
                config.glow_thickness * (1.0f - i * 0.2f));
    }
}

void ESPRenderer::RenderSkeleton(const PlayerEntity& player, const ESPConfig& config) {
    if (!config.skeleton_enabled) {
        return;
    }
    
    DirectX::XMFLOAT3 head_pos = player.position;
    DirectX::XMFLOAT3 neck_pos{
        head_pos.x,
        head_pos.y,
        head_pos.z - 10.0f
    };
    
    // Calculate screen positions for skeleton bones
    auto get_screen_pos = [&](const DirectX::XMFLOAT3& world) -> DirectX::XMFLOAT2 {
        return CalculateScreenPosition(world, config);
    };
    
    DirectX::XMFLOAT3 color = GetTeamColor(player.team, false);
    
    // Head to neck
    DrawLine(get_screen_pos(head_pos), get_screen_pos(neck_pos), color, config.bone_size);
    
    // Simple bone structure based on stance
    float shoulder_width = player.screen_width * 0.6f;
    float hip_width = player.screen_width * 0.7f;
    float torso_height = player.screen_height * 0.4f;
    
    DirectX::XMFLOAT2 neck_screen = get_screen_pos(neck_pos);
    DirectX::XMFLOAT2 hip_screen{
        neck_screen.x,
        neck_screen.y + torso_height
    };
    
    // Shoulders (left and right)
    DirectX::XMFLOAT2 left_shoulder{
        neck_screen.x - shoulder_width / 2.0f,
        neck_screen.y
    };
    DirectX::XMFLOAT2 right_shoulder{
        neck_screen.x + shoulder_width / 2.0f,
        neck_screen.y
    };
    
    // Hips (left and right)
    DirectX::XMFLOAT2 left_hip{
        hip_screen.x - hip_width / 2.0f,
        hip_screen.y
    };
    DirectX::XMFLOAT2 right_hip{
        hip_screen.x + hip_width / 2.0f,
        hip_screen.y
    };
    
    // Draw torso connections
    DrawLine(left_shoulder, right_shoulder, color, config.bone_size);
    DrawLine(left_hip, right_hip, color, config.bone_size);
    DrawLine(left_shoulder, left_hip, color, config.bone_size);
    DrawLine(right_shoulder, right_hip, color, config.bone_size);
    
    // Arms
    DirectX::XMFLOAT2 left_hand{
        left_shoulder.x - player.screen_width * 0.4f,
        left_shoulder.y + torso_height * 0.5f
    };
    DirectX::XMFLOAT2 right_hand{
        right_shoulder.x + player.screen_width * 0.4f,
        right_shoulder.y + torso_height * 0.5f
    };
    
    DrawLine(left_shoulder, left_hand, color, config.bone_size);
    DrawLine(right_shoulder, right_hand, color, config.bone_size);
    
    // Legs
    DirectX::XMFLOAT2 left_foot{
        left_hip.x,
        left_hip.y + player.screen_height * 0.5f
    };
    DirectX::XMFLOAT2 right_foot{
        right_hip.x,
        right_hip.y + player.screen_height * 0.5f
    };
    
    DrawLine(left_hip, left_foot, color, config.bone_size);
    DrawLine(right_hip, right_foot, color, config.bone_size);
}

void ESPRenderer::RenderHealthBar(const PlayerEntity& player, const ESPConfig& config) {
    if (!config.health_bar_enabled) {
        return;
    }
    
    DirectX::XMFLOAT2 pos{
        player.screen_position.x + player.screen_width / 2.0f + 5.0f,
        player.screen_position.y - player.screen_height
    };
    
    float bar_height = config.health_bar_height;
    float bar_width = config.health_bar_width;
    
    // Background (empty health)
    FillRect(pos, {bar_width, bar_height}, {0.1f, 0.1f, 0.1f}, 0.8f);
    
    // Calculate health ratio
    float health_ratio = static_cast<float>(player.health) / 
                        static_cast<float>(player.max_health);
    
    // Health bar (green to red gradient)
    DirectX::XMFLOAT3 health_color{};
    if (health_ratio > 0.6f) {
        health_color = {0.2f, 1.0f, 0.2f};  // Green
    } else if (health_ratio > 0.3f) {
        health_color = {1.0f, 1.0f, 0.2f};  // Yellow
    } else {
        health_color = {1.0f, 0.2f, 0.2f};  // Red
    }
    
    float health_height = bar_height * health_ratio;
    FillRect({pos.x, pos.y + bar_height - health_height}, 
             {bar_width, health_height}, health_color);
    
    // Shield bar if enabled
    if (config.show_shield_bar && player.shield > 0) {
        float shield_ratio = static_cast<float>(player.shield) / 
                            static_cast<float>(player.max_shield);
        
        DirectX::XMFLOAT3 shield_color{0.2f, 0.6f, 1.0f};  // Blue
        
        float shield_height = bar_height * shield_ratio;
        FillRect({pos.x - bar_width - 3.0f, pos.y + bar_height - shield_height},
                 {bar_width, shield_height}, shield_color);
    }
}

void ESPRenderer::RenderDistance(const PlayerEntity& player, const ESPConfig& config) {
    if (!config.distance_enabled) {
        return;
    }
    
    DirectX::XMFLOAT2 pos{
        player.screen_position.x,
        player.screen_position.y + player.screen_height / 2.0f
    };
    
    std::ostringstream oss;
    if (config.show_distance_in_units) {
        oss << static_cast<uint32_t>(player.distance_to_player) << "u";
    } else {
        // Convert to feet (Apex standard)
        float feet = player.distance_to_player * 0.5f;
        oss << static_cast<uint32_t>(feet) << "'";
    }
    
    std::string distance_text = oss.str();
    
    // Color based on distance
    DirectX::XMFLOAT3 color{};
    if (player.distance_to_player < 500.0f) {
        color = {0.2f, 1.0f, 0.2f};  // Close - green
    } else if (player.distance_to_player < 1500.0f) {
        color = {1.0f, 1.0f, 0.2f};  // Medium - yellow
    } else {
        color = {1.0f, 0.2f, 0.2f};  // Far - red
    }
    
    DrawText(pos, distance_text, color, config.text_size * 0.8f);
}

void ESPRenderer::RenderSnapline(const PlayerEntity& player, const ESPConfig& config) {
    if (!config.snaplines_enabled) {
        return;
    }
    
    // Center of screen
    DirectX::XMFLOAT2 center{
        static_cast<float>(screen_width_) / 2.0f,
        static_cast<float>(screen_height_) / 2.0f
    };
    
    // Player position (bottom center of box)
    DirectX::XMFLOAT2 player_pos{
        player.screen_position.x,
        player.screen_position.y + player.screen_height
    };
    
    // Snapline color (gray by default, team-colored for teammates)
    DirectX::XMFLOAT3 color = config.snapline_color;
    if (player.is_teammate) {
        color = GetTeamColor(player.team, false);
    }
    
    DrawLine(center, player_pos, color, 1.0f, true);
}

void ESPRenderer::RenderName(const PlayerEntity& player, const ESPConfig& config) {
    DirectX::XMFLOAT2 pos{
        player.screen_position.x,
        player.screen_position.y - player.screen_height - 25.0f
    };
    
    std::ostringstream oss;

    // Legend name
    oss << EntityExtractor::GetLegendDisplayName(player.legend_name);
    
    // Player name if not local
    if (!player.is_local_player) {
        oss << " | " << player.player_name;
    }
    
    // Team tag
    if (player.is_teammate) {
        oss << " [TEAM]";
    } else if (player.state == PlayerState::DEAD) {
        oss << " [DEAD]";
    }
    
    std::string name_text = oss.str();
    
    // Color based on team and state
    DirectX::XMFLOAT3 color{};
    if (player.is_local_player) {
        color = {1.0f, 1.0f, 0.8f};  // White for local
    } else if (player.is_teammate) {
        color = GetTeamColor(player.team, false);
    } else if (player.state == PlayerState::DEAD) {
        color = {0.6f, 0.6f, 0.6f};  // Gray for dead
    } else {
        color = GetTeamColor(player.team, false);
    }
    
    DrawText(pos, name_text, color, config.text_size);
}

void ESPRenderer::RenderState(const PlayerEntity& player, const ESPConfig& config) {
    DirectX::XMFLOAT2 pos{
        player.screen_position.x + player.screen_width / 2.0f + 5.0f,
        player.screen_position.y - player.screen_height + 10.0f
    };
    
    std::string state_text{};
    DirectX::XMFLOAT3 color{};
    
    switch (player.state) {
        case PlayerState::ALIVE:
            state_text = "ALIVE";
            color = {0.2f, 1.0f, 0.2f};
            break;
        case PlayerState::DYING:
            state_text = "DYING";
            color = {1.0f, 0.6f, 0.2f};
            break;
        case PlayerState::DEAD:
            state_text = "DEAD";
            color = {0.8f, 0.4f, 0.4f};
            break;
        case PlayerState::SPAWNING:
            state_text = "SPAWN";
            color = {0.2f, 0.6f, 1.0f};
            break;
        default:
            state_text = "UNKNOWN";
            color = {0.6f, 0.6f, 0.6f};
            break;
    }
    
    DrawText(pos, state_text, color, config.text_size * 0.7f);
}

DirectX::XMFLOAT3 ESPRenderer::GetTeamColor(Team team, bool use_glow) const {
    if (use_glow && config_.use_glow_colors) {
        return GLOW_COLORS[static_cast<int>(team)];
    }
    return TEAM_COLORS[static_cast<int>(team)];
}

DirectX::XMFLOAT2 ESPRenderer::CalculateScreenPosition(const DirectX::XMFLOAT3& world_pos,
                                                         const ESPConfig& config) const {
    // Simple perspective projection
    float fov = config_.FOV > 0 ? config_.FOV : 90.0f;
    float fov_scale = screen_width_ / (2.0f * tanf(fov * DirectX::XM_PI / 180.0f / 2.0f));
    
    // Calculate screen position
    float x = screen_width_ / 2.0f + world_pos.x * fov_scale / world_pos.z;
    float y = screen_height_ / 2.0f - world_pos.y * fov_scale / world_pos.z;
    
    return {x, y};
}

DirectX::XMFLOAT2 ESPRenderer::CalculateScreenPositionWithCamera(
    const DirectX::XMFLOAT3& world_pos,
    const DirectX::XMFLOAT3& cam_position,
    const DirectX::XMFLOAT3& cam_angles,  // yaw in radians, pitch in radians
    float fov, int screen_width, int screen_height) const {
    
    // Calculate vector from camera to target
    DirectX::XMFLOAT3 delta;
    delta.x = world_pos.x - cam_position.x;
    delta.y = world_pos.y - cam_position.y;
    delta.z = world_pos.z - cam_position.z;
    
    // Calculate forward vector from yaw/pitch
    float cos_yaw = cosf(cam_angles.x);
    float sin_yaw = sinf(cam_angles.x);
    float cos_pitch = cosf(cam_angles.y);
    float sin_pitch = sinf(cam_angles.y);
    
    DirectX::XMFLOAT3 forward{sin_yaw * cos_pitch, sin_pitch, cos_yaw * cos_pitch};
    
    // Calculate right vector (cross product of forward and up)
    // Up is typically (0, 1, 0) in Apex's coordinate system
    DirectX::XMFLOAT3 right;
    right.x = forward.z;
    right.y = 0.0f;
    right.z = -forward.x;
    
    // Normalize right vector
    float right_len = sqrtf(right.x * right.x + right.z * right.z);
    if (right_len > 0.001f) {
        right.x /= right_len;
        right.z /= right_len;
    }
    
    // Calculate up vector (cross product of right and forward)
    DirectX::XMFLOAT3 up;
    up.x = right.y * forward.z - right.z * forward.y;
    up.y = right.z * forward.x - right.x * forward.z;
    up.z = right.x * forward.y - right.y * forward.x;
    
    // Project onto camera axes
    float x = delta.x * right.x + delta.y * right.y + delta.z * right.z;
    float y = delta.x * up.x + delta.y * up.y + delta.z * up.z;
    float z = delta.x * forward.x + delta.y * forward.y + delta.z * forward.z;
    
    // Check if target is in front of camera
    if (z <= 0.1f) return {screen_width / 2, screen_height / 2};
    
    // Calculate FOV scale
    float fov_scale = screen_width / (2.0f * tanf(fov * DirectX::XM_PI / 180.0f / 2.0f));
    
    // Calculate screen position
    float sx = screen_width / 2.0f + x * fov_scale / z;
    float sy = screen_height / 2.0f - y * fov_scale / z;
    
    return {sx, sy};
}

void ESPRenderer::DrawLine(const DirectX::XMFLOAT2& start, const DirectX::XMFLOAT2& end,
                          const DirectX::XMFLOAT3& color, float thickness,
                          bool dashed) {
    // Calculate line properties
    float dx = end.x - start.x;
    float dy = end.y - start.y;
    float length = sqrtf(dx * dx + dy * dy);
    
    if (length < 0.5f) {
        return;
    }
    
    // Normalize direction
    float inv_length = 1.0f / length;
    float dir_x = dx * inv_length;
    float dir_y = dy * inv_length;
    
    // Perpendicular vector for thickness
    float perp_x = -dir_y;
    float perp_y = dir_x;
    
    // Calculate corner points
    DirectX::XMFLOAT2 corners[4]{
        {start.x - (dir_x * thickness + perp_x * thickness) / 2.0f,
         start.y - (dir_y * thickness + perp_y * thickness) / 2.0f},
        {start.x + (dir_x * thickness - perp_x * thickness) / 2.0f,
         start.y + (dir_y * thickness - perp_y * thickness) / 2.0f},
        {end.x + (dir_x * thickness - perp_x * thickness) / 2.0f,
         end.y + (dir_y * thickness - perp_y * thickness) / 2.0f},
        {end.x - (dir_x * thickness + perp_x * thickness) / 2.0f,
         end.y - (dir_y * thickness + perp_y * thickness) / 2.0f}
    };
    
    // Draw line with dashed pattern if enabled
    if (dashed) {
        float dash_length = 8.0f;
        float gap_length = 4.0f;
        float total_length = dash_length + gap_length;
        
        for (float t = 0; t < length; t += total_length) {
            float dash_end = std::min(t + dash_length, length);
            
            // Interpolate start and end points for this dash
            DirectX::XMFLOAT2 dash_start{
                start.x + dir_x * t,
                start.y + dir_y * t
            };
            DirectX::XMFLOAT2 dash_end_pos{
                start.x + dir_x * dash_end,
                start.y + dir_y * dash_end
            };
            
            // Draw this dash segment
            float dash_thickness = thickness;
            DirectX::XMFLOAT2 dash_corners[4]{
                {dash_start.x - (dir_x * dash_thickness + perp_x * dash_thickness) / 2.0f,
                 dash_start.y - (dir_y * dash_thickness + perp_y * dash_thickness) / 2.0f},
                {dash_start.x + (dir_x * dash_thickness - perp_x * dash_thickness) / 2.0f,
                 dash_start.y + (dir_y * dash_thickness - perp_y * dash_thickness) / 2.0f},
                {dash_end_pos.x + (dir_x * dash_thickness - perp_x * dash_thickness) / 2.0f,
                 dash_end_pos.y + (dir_y * dash_thickness - perp_y * dash_thickness) / 2.0f},
                {dash_end_pos.x - (dir_x * dash_thickness + perp_x * dash_thickness) / 2.0f,
                 dash_end_pos.y - (dir_y * dash_thickness + perp_y * dash_thickness) / 2.0f}
            };
            
            // Render this dash segment (simplified as filled quad)
            FillRect(dash_corners[0], {dash_corners[2].x - dash_corners[0].x,
                                       dash_corners[2].y - dash_corners[0].y},
                    color);
        }
    } else {
        // Solid line - render as filled quad
        FillRect(corners[0], {corners[2].x - corners[0].x,
                             corners[2].y - corners[0].y}, color);
    }
}

void ESPRenderer::DrawRect(const DirectX::XMFLOAT2& pos, const DirectX::XMFLOAT2& size,
                          const DirectX::XMFLOAT3& color, float thickness,
                          BoxStyle style) {
    // Calculate corners
    DirectX::XMFLOAT2 bottom_right{
        pos.x + size.x,
        pos.y + size.y
    };

    // Top side
    DrawLine(pos, {bottom_right.x, pos.y}, color, thickness);
    // Bottom side
    DrawLine({pos.x, bottom_right.y}, bottom_right, color, thickness);
    // Left side
    DrawLine(pos, {pos.x, bottom_right.y}, color, thickness);
    // Right side
    DrawLine({bottom_right.x, pos.y}, bottom_right, color, thickness);

    if (style == BoxStyle::FILLED || style == BoxStyle::ROUNDED) {
        FillRect(pos, size, color, 0.1f);
    }
}

void ESPRenderer::FillRect(const DirectX::XMFLOAT2& pos, const DirectX::XMFLOAT2& size,
                          const DirectX::XMFLOAT3& color, float alpha) {
    // Calculate bottom_right corner
    DirectX::XMFLOAT2 bottom_right{
        pos.x + size.x,
        pos.y + size.y
    };

    // Create rectangle geometry
    DirectX::XMFLOAT2 corners[4]{
        pos,
        {pos.x + size.x, pos.y},
        bottom_right,
        {pos.x, pos.y + size.y}
    };

    // Calculate center for gradient fill
    DirectX::XMFLOAT2 center{
        pos.x + size.x / 2.0f,
        pos.y + size.y / 2.0f
    };
    
    // Render filled rectangle (simplified - could use vertex buffer for complex fills)
    float max_dist = sqrtf(size.x * size.x + size.y * size.y) / 2.0f;
    
    for (int y = 0; y < static_cast<int>(size.y); ++y) {
        for (int x = 0; x < static_cast<int>(size.x); ++x) {
            DirectX::XMFLOAT2 pixel_pos{
                pos.x + static_cast<float>(x),
                pos.y + static_cast<float>(y)
            };
            
            float dist_to_center = sqrtf((pixel_pos.x - center.x) * (pixel_pos.x - center.x) +
                                         (pixel_pos.y - center.y) * (pixel_pos.y - center.y));
            float gradient_alpha = alpha * (1.0f - dist_to_center / max_dist);
            
            // Simple pixel rendering (would be optimized with vertex buffer in production)
            // For now, just render as a series of lines
        }
    }
    
    // Draw border if needed
    DrawRect(pos, size, color, 1.0f);
}

void ESPRenderer::DrawText(const DirectX::XMFLOAT2& pos, const std::string& text,
                          const DirectX::XMFLOAT3& color, float size, bool shadow) {
    // Calculate text dimensions (approximate)
    float text_width = static_cast<float>(text.length()) * size * 0.6f;
    float text_height = size * 1.2f;
    
    // Shadow if enabled
    if (shadow) {
        DirectX::XMFLOAT3 shadow_color{0.0f, 0.0f, 0.0f};
        FillRect({pos.x + 2.0f, pos.y + 2.0f}, {text_width, text_height}, shadow_color, 0.5f);
    }
    
    // Text background
    FillRect(pos, {text_width, text_height}, color, 0.15f);
    
    // Draw text outline
    DrawRect(pos, {text_width, text_height}, color, 1.0f);
}

std::vector<std::pair<DirectX::XMFLOAT2, DirectX::XMFLOAT2>>
    ESPRenderer::CalculateCorners(const DirectX::XMFLOAT2& pos,
                                   const DirectX::XMFLOAT2& size,
                                   float corner_size) const {
    std::vector<std::pair<DirectX::XMFLOAT2, DirectX::XMFLOAT2>> corners;
    
    // Top-left corner
    corners.emplace_back(
        DirectX::XMFLOAT2{pos.x, pos.y + corner_size},
        DirectX::XMFLOAT2{pos.x, pos.y}
    );
    corners.emplace_back(
        DirectX::XMFLOAT2{pos.x, pos.y},
        DirectX::XMFLOAT2{pos.x + corner_size, pos.y}
    );
    
    // Top-right corner
    corners.emplace_back(
        DirectX::XMFLOAT2{pos.x + size.x - corner_size, pos.y},
        DirectX::XMFLOAT2{pos.x + size.x, pos.y}
    );
    corners.emplace_back(
        DirectX::XMFLOAT2{pos.x + size.x, pos.y},
        DirectX::XMFLOAT2{pos.x + size.x, pos.y + corner_size}
    );
    
    // Bottom-right corner
    corners.emplace_back(
        DirectX::XMFLOAT2{pos.x + size.x, pos.y + size.y - corner_size},
        DirectX::XMFLOAT2{pos.x + size.x, pos.y + size.y}
    );
    corners.emplace_back(
        DirectX::XMFLOAT2{pos.x + size.x, pos.y + size.y},
        DirectX::XMFLOAT2{pos.x + size.x - corner_size, pos.y + size.y}
    );
    
    // Bottom-left corner
    corners.emplace_back(
        DirectX::XMFLOAT2{pos.x + corner_size, pos.y + size.y},
        DirectX::XMFLOAT2{pos.x, pos.y + size.y}
    );
    corners.emplace_back(
        DirectX::XMFLOAT2{pos.x, pos.y + size.y},
        DirectX::XMFLOAT2{pos.x, pos.y + size.y - corner_size}
    );
    
    return corners;
}
