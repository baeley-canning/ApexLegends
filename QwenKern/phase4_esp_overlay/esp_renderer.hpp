#pragma once
#ifndef ESP_RENDERER_HPP
#define ESP_RENDERER_HPP

#include <Windows.h>
#include <d3d11.h>
#include <d3d12.h>
#include <DirectXMath.h>
#include <string>
#include <vector>
#include <functional>

// Forward declarations
struct PlayerEntity;
class EntityExtractor;

// Forward declare Team (defined in entity_extractor.hpp)
enum class Team : uint8_t;

// ESP feature flags for toggling visual components
enum class ESPFeature : uint32_t {
    BOX = 0x01,
    GLOW = 0x02,
    SKELETON = 0x04,
    HEALTH_BAR = 0x08,
    DISTANCE = 0x10,
    SNAPLINES = 0x20,
    NAME = 0x40,
    LEGEND_NAME = 0x80,
    SHIELD = 0x100,
    STATE = 0x200,
};

// Box style enumeration
enum class BoxStyle : uint8_t {
    OUTLINE = 0,      // Basic outline box
    FILLED = 1,       // Filled background with outline
    CORNER = 2,       // Corner boxes (Kernaim-style)
    ROUNDED = 3,      // Rounded corners
    DASHED = 4,       // Dashed outline
};

// ESP configuration structure
struct ESPConfig {
    // General settings
    bool enabled = true;
    uint32_t update_interval_ms = 16;  // ~60 FPS

    // Screen dimensions (for perspective projection)
    uint32_t screen_width = 1920;
    uint32_t screen_height = 1080;
    float FOV = 90.0f;

    // Box settings
    BoxStyle box_style = BoxStyle::CORNER;
    float box_padding = 4.0f;
    float corner_size = 8.0f;
    float line_thickness = 1.5f;
    
    // Glow settings
    bool glow_enabled = true;
    float glow_intensity = 0.8f;
    float glow_thickness = 2.0f;
    bool dynamic_glow = true;  // Changes with distance
    
    // Skeleton settings
    bool skeleton_enabled = true;
    float bone_size = 2.0f;
    std::vector<std::pair<uint32_t, uint32_t>> bone_connections;
    
    // Health bar settings
    bool health_bar_enabled = true;
    float health_bar_width = 3.0f;
    float health_bar_height = 40.0f;
    bool show_shield_bar = true;
    
    // Distance settings
    bool distance_enabled = true;
    bool show_distance_in_units = false;
    
    // Snapline settings
    bool snaplines_enabled = true;
    DirectX::XMFLOAT3 snapline_color = {0.5f, 0.5f, 0.5f};
    
    // Text settings
    float text_size = 12.0f;
    bool shadow_text = true;
    
    // Team colors
    bool team_colors_enabled = true;
    bool use_glow_colors = true;
    
    // Humanized features (Wraith tight, Gibraltar loose)
    bool humanized_features_enabled = true;
};

// ESP renderer class for DirectX overlay rendering
class ESPRenderer {
public:
    ESPRenderer();
    ~ESPRenderer();
    
    // Initialize DirectX and ESP rendering
    bool Initialize(HWND game_hwnd);
    
    // Shutdown DirectX resources
    void Shutdown();
    
    // Render ESP for all entities
    void Render(const std::vector<PlayerEntity>& entities, 
                const EntityExtractor& extractor,
                const ESPConfig& config);
    
    // Toggle ESP feature
    void ToggleFeature(ESPFeature feature, bool enabled = true);
    
    // Update configuration
    void UpdateConfig(const ESPConfig& config);
    
    // Get current configuration
    const ESPConfig& GetConfig() const { return config_; }
    
    // Toggle ESP on/off
    void SetEnabled(bool enabled) { config_.enabled = enabled; }
    bool IsEnabled() const { return config_.enabled; }

private:
    // DirectX components
    IDXGISwapChain* swap_chain_ = nullptr;
    ID3D11Device* d3d11_device_ = nullptr;
    ID3D11DeviceContext* d3d11_context_ = nullptr;
    ID3D12Device* d3d12_device_ = nullptr;
    ID3D12CommandQueue* command_queue_ = nullptr;
    
    // Render targets
    ID3D11Texture2D* back_buffer_ = nullptr;
    ID3D11RenderTargetView* rtv_ = nullptr;
    
    // Pre-render setup
    void BeginRender();
    void EndRender();
    
    // Render individual entity
    void RenderEntity(const PlayerEntity& player,
                      const EntityExtractor& extractor,
                      const ESPConfig& config);
    
    // Render box around entity
    void RenderBox(const PlayerEntity& player, const ESPConfig& config);
    
    // Render glow effect
    void RenderGlow(const PlayerEntity& player, const ESPConfig& config);
    
    // Render skeleton
    void RenderSkeleton(const PlayerEntity& player, const ESPConfig& config);
    
    // Render health bar
    void RenderHealthBar(const PlayerEntity& player, const ESPConfig& config);
    
    // Render distance indicator
    void RenderDistance(const PlayerEntity& player, const ESPConfig& config);
    
    // Render snapline to center screen
    void RenderSnapline(const PlayerEntity& player, const ESPConfig& config);
    
    // Render name and legend
    void RenderName(const PlayerEntity& player, const ESPConfig& config);
    
    // Render state indicator (alive/dead, etc.)
    void RenderState(const PlayerEntity& player, const ESPConfig& config);
    
    // Helper: get team color with glow support
    DirectX::XMFLOAT3 GetTeamColor(Team team, bool use_glow) const;
    
    // Helper: calculate screen position from world position
    DirectX::XMFLOAT2 CalculateScreenPosition(const DirectX::XMFLOAT3& world_pos,
                                               const ESPConfig& config) const;

    // Helper: calculate screen position using camera data (proper W2S with yaw/pitch)
    DirectX::XMFLOAT2 CalculateScreenPositionWithCamera(
        const DirectX::XMFLOAT3& world_pos,
        const DirectX::XMFLOAT3& cam_position,
        const DirectX::XMFLOAT3& cam_angles,  // yaw in radians, pitch in radians
        float fov, int screen_width, int screen_height) const;

    // Create an independent overlay window on top of the game window
    static HWND CreateOverlayWindow(HWND game_hwnd);

    // Update overlay position to match game window position/size
    void UpdateOverlayPosition();
    
    // Helper: draw line with thickness
    void DrawLine(const DirectX::XMFLOAT2& start, const DirectX::XMFLOAT2& end,
                  const DirectX::XMFLOAT3& color, float thickness,
                  bool dashed = false);
    
    // Helper: draw rectangle
    void DrawRect(const DirectX::XMFLOAT2& pos, const DirectX::XMFLOAT2& size,
                  const DirectX::XMFLOAT3& color, float thickness,
                  BoxStyle style = BoxStyle::OUTLINE);
    
    // Helper: fill rectangle
    void FillRect(const DirectX::XMFLOAT2& pos, const DirectX::XMFLOAT2& size,
                  const DirectX::XMFLOAT3& color, float alpha = 1.0f);
    
    // Helper: draw text
    void DrawText(const DirectX::XMFLOAT2& pos, const std::string& text,
                  const DirectX::XMFLOAT3& color, float size,
                  bool shadow = true);
    
    // Helper: calculate corner points for box
    std::vector<std::pair<DirectX::XMFLOAT2, DirectX::XMFLOAT2>> 
        CalculateCorners(const DirectX::XMFLOAT2& pos, const DirectX::XMFLOAT2& size,
                        float corner_size) const;
    
    // DirectX 12 pipeline state (optional for D3D12 path)
    struct D3D12PipelineState {
        ID3D12DescriptorHeap* rtv_heap = nullptr;
        ID3D12GraphicsCommandList* cmd_list = nullptr;
        ID3D12Resource* render_target = nullptr;
        D3D12_CPU_DESCRIPTOR_HANDLE rtv_handle{};
    };
    
    D3D12PipelineState d3d12_state_;

    // Overlay window handle (independent window on top of game)
    HWND overlay_window_ = nullptr;
    
    // Whether we're using an independent overlay or rendering into the game window
    bool use_overlay_window_ = false;

private:
    // Current configuration
    ESPConfig config_;
    
    // Active features bitmask
    uint32_t active_features_ = 0xFFFFFFFF;
    
    // Screen dimensions
    uint32_t screen_width_ = 1920;
    uint32_t screen_height_ = 1080;
    
    // Cached colors for team differentiation
    static constexpr DirectX::XMFLOAT3 TEAM_COLORS[8] = {
        {1.0f, 0.2f, 0.2f},   // RED
        {0.2f, 0.4f, 1.0f},   // BLUE
        {0.2f, 0.8f, 0.3f},   // GREEN
        {1.0f, 0.6f, 0.2f},   // ORANGE
        {0.7f, 0.3f, 0.9f},   // PURPLE
        {1.0f, 0.9f, 0.2f},   // YELLOW
        {0.2f, 0.8f, 0.8f},   // TEAL
        {1.0f, 0.3f, 0.6f},   // PINK
    };
    
    static constexpr DirectX::XMFLOAT3 GLOW_COLORS[8] = {
        {1.0f, 0.4f, 0.2f},   // RED glow
        {0.4f, 0.6f, 1.0f},   // BLUE glow
        {0.4f, 0.9f, 0.5f},   // GREEN glow
        {1.0f, 0.7f, 0.4f},   // ORANGE glow
        {0.9f, 0.5f, 1.0f},   // PURPLE glow
        {1.0f, 1.0f, 0.4f},   // YELLOW glow
        {0.4f, 0.9f, 0.9f},   // TEAL glow
        {1.0f, 0.5f, 0.7f},   // PINK glow
    };
};

#endif // ESP_RENDERER_HPP
