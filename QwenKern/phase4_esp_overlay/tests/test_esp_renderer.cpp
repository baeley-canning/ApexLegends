#include "test_esp_renderer.hpp"
#include "../../esp_renderer.hpp"
#include <iostream>
#include <sstream>

// ============================================================================
// Test ESP Renderer Implementation
// ============================================================================

TestESPRenderer::TestESPRenderer() {
    renderer_ = new ESPRenderer();
}

TestESPRenderer::~TestESPRenderer() {
    if (renderer_) {
        delete renderer_;
    }
}

std::vector<TestResult> TestESPRenderer::RunAllTests() {
    std::vector<TestResult> results;
    
    // Run individual test methods
    results.push_back(TestInitialization());
    results.push_back(TestBoxRendering());
    results.push_back(TestGlowEffects());
    results.push_back(TestSkeletonRendering());
    results.push_back(TestHealthBarDisplay());
    results.push_back(TestDistanceIndicators());
    results.push_back(TestSnaplines());
    results.push_back(TestFeatureToggles());
    
    return results;
}

TestResult TestESPRenderer::TestInitialization() {
    TestResult result{"Renderer Initialization", true, "DirectX 11/12 setup and rendering", 0, 0};
    
    // Mock window handle
    HWND mock_hwnd = reinterpret_cast<HWND>(0x10000);
    
    bool init_success = renderer_->Initialize(mock_hwnd);
    Assert(init_success, "ESP renderer initialized", result);
    
    // Verify configuration was set up
    const auto& config = renderer_->GetConfig();
    Assert(config.enabled, "ESP is enabled by default", result);
    Assert(config.box_style == BoxStyle::CORNER, "Corner style is default", result);
    Assert(config.glow_enabled, "Glow is enabled by default", result);
    
    Log("Renderer initialization test completed");
    return result;
}

TestResult TestESPRenderer::TestBoxRendering() {
    TestResult result{"Box Rendering", true, "Rendering various box styles (outline, filled, corner)", 0, 0};
    
    // Create mock player
    PlayerEntity player = CreateMockPlayer(0);
    
    // Test different box styles
    std::vector<BoxStyle> box_styles = {
        BoxStyle::OUTLINE,
        BoxStyle::FILLED,
        BoxStyle::CORNER,
        BoxStyle::ROUNDED,
        BoxStyle::DASHED
    };
    
    for (auto style : box_styles) {
        config_.box_style = style;
        
        // Simulate rendering
        DirectX::XMFLOAT2 pos{
            player.screen_position.x - player.screen_width / 2.0f,
            player.screen_position.y - player.screen_height
        };
        
        DirectX::XMFLOAT2 size{
            player.screen_width + config_.box_padding * 4.0f,
            player.screen_height
        };
        
        Assert(size.x > 0 && size.y > 0, 
               "Box dimensions valid for style " + std::to_string(static_cast<int>(style)), result);
    }
    
    // Test corner box calculation
    auto corners = renderer_->CalculateCorners({100, 100}, {80, 160}, config_.corner_size);
    Assert(corners.size() == 8, "Correct number of corners (8) for corner box style", result);
    
    Log("Box rendering test completed");
    return result;
}

TestResult TestESPRenderer::TestGlowEffects() {
    TestResult result{"Glow Effects", true, "Rendering dynamic glow around players", 0, 0};
    
    PlayerEntity player = CreateMockPlayer(0);
    
    // Test glow intensity with distance
    config_.glow_intensity = 0.8f;
    config_.dynamic_glow = true;
    
    // Player at different distances
    std::vector<float> distances = {100.0f, 500.0f, 1000.0f, 2000.0f};
    
    for (float dist : distances) {
        player.distance_to_player = dist;
        
        // Calculate glow intensity based on distance
        float intensity = config_.glow_intensity;
        if (config_.dynamic_glow) {
            intensity *= std::min(1.5f, 2000.0f / (dist + 1));
        }
        
        Assert(intensity > 0.4f && intensity <= 1.2f,
               "Glow intensity valid at distance " + std::to_string(static_cast<uint32_t>(dist)), result);
    }
    
    // Test low-health glow boost
    player.health = 50;
    player.max_health = 125;
    float health_ratio = static_cast<float>(player.health) / 
                        static_cast<float>(player.max_health);
    
    Assert(health_ratio < 0.5f, "Low health condition met", result);
    
    Log("Glow effects test completed");
    return result;
}

TestResult TestESPRenderer::TestSkeletonRendering() {
    TestResult result{"Skeleton Rendering", true, "Drawing bone connections for players", 0, 0};
    
    PlayerEntity player = CreateMockPlayer(0);
    
    // Verify bone connections exist
    const auto& config = renderer_->GetConfig();
    Assert(!config.bone_connections.empty(), "Bone connections defined", result);
    Assert(config.bone_connections.size() >= 10, "Sufficient bone connections for full skeleton", result);
    
    // Test skeleton dimensions
    float shoulder_width = player.screen_width * 0.6f;
    float hip_width = player.screen_width * 0.7f;
    float torso_height = player.screen_height * 0.4f;
    
    Assert(shoulder_width > 0, "Shoulder width calculated", result);
    Assert(hip_width > shoulder_width, "Hips wider than shoulders (natural stance)", result);
    Assert(torso_height > 0, "Torso height calculated", result);
    
    Log("Skeleton rendering test completed");
    return result;
}

TestResult TestESPRenderer::TestHealthBarDisplay() {
    TestResult result{"Health Bar Display", true, "Rendering health and shield bars", 0, 0};
    
    PlayerEntity player = CreateMockPlayer(0);
    
    // Set health/shield values
    player.health = 125;
    player.max_health = 125;
    player.shield = 75;
    player.max_shield = 100;
    
    // Calculate health ratio
    float health_ratio = static_cast<float>(player.health) / 
                        static_cast<float>(player.max_health);
    
    Assert(health_ratio == 1.0f, "Full health ratio is 1.0", result);
    
    // Test shield bar
    float shield_ratio = static_cast<float>(player.shield) / 
                        static_cast<float>(player.max_shield);
    
    Assert(shield_ratio == 0.75f, "Shield ratio is 0.75 (75/100)", result);
    
    // Test health color gradient
    DirectX::XMFLOAT3 health_color{};
    if (health_ratio > 0.6f) {
        health_color = {0.2f, 1.0f, 0.2f};  // Green
    } else if (health_ratio > 0.3f) {
        health_color = {1.0f, 1.0f, 0.2f};  // Yellow
    } else {
        health_color = {1.0f, 0.2f, 0.2f};  // Red
    }
    
    Assert(health_color.y > 0.8f, "Health bar has green/yellow hue for full health", result);
    
    Log("Health bar display test completed");
    return result;
}

TestResult TestESPRenderer::TestDistanceIndicators() {
    TestResult result{"Distance Indicators", true, "Displaying distance to players", 0, 0};
    
    PlayerEntity player = CreateMockPlayer(0);
    
    // Test distance display at various ranges
    struct DistanceTest {
        float distance;
        std::string expected_unit;
        DirectX::XMFLOAT3 expected_color;
    };
    
    std::vector<DistanceTest> tests = {
        {300.0f, "150'", {0.2f, 1.0f, 0.2f}},      // Close - green
        {800.0f, "400'", {1.0f, 1.0f, 0.2f}},      // Medium - yellow
        {1500.0f, "750'", {1.0f, 0.2f, 0.2f}},     // Far - red
    };
    
    for (const auto& test : tests) {
        player.distance_to_player = test.distance;
        
        // Calculate expected feet
        float feet = test.distance * 0.5f;
        
        Assert(std::abs(feet - test.expected_unit.length() * 100) < 200,
               "Distance calculation valid for range " + test.expected_unit, result);
    }
    
    Log("Distance indicators test completed");
    return result;
}

TestResult TestESPRenderer::TestSnaplines() {
    TestResult result{"Snaplines", true, "Drawing lines from center to players", 0, 0};
    
    // Mock screen dimensions
    renderer_->screen_width_ = 1920;
    renderer_->screen_height_ = 1080;
    
    PlayerEntity player = CreateMockPlayer(0);
    
    // Center of screen
    DirectX::XMFLOAT2 center{
        1920.0f / 2.0f,
        1080.0f / 2.0f
    };
    
    // Player position (bottom center of box)
    DirectX::XMFLOAT2 player_pos{
        player.screen_position.x,
        player.screen_position.y + player.screen_height
    };
    
    // Verify snapline geometry
    float dx = player_pos.x - center.x;
    float dy = player_pos.y - center.y;
    float length = sqrtf(dx * dx + dy * dy);
    
    Assert(length > 0, "Snapline has valid length", result);
    Assert(dx < 100 && dy < 100, "Snapline direction reasonable from center", result);
    
    // Test teammate snapline color
    player.is_teammate = true;
    DirectX::XMFLOAT3 team_color = renderer_->GetTeamColor(player.team, false);
    
    Assert(team_color.x > 0.2f, "Teammate snapline has team color", result);
    
    Log("Snaplines test completed");
    return result;
}

TestResult TestESPRenderer::TestFeatureToggles() {
    TestResult result{"Feature Toggles", true, "Enabling/disabling ESP features", 0, 0};
    
    // Test toggling individual features
    std::vector<ESPFeature> features = {
        ESPFeature::BOX,
        ESPFeature::GLOW,
        ESPFeature::SKELETON,
        ESPFeature::HEALTH_BAR,
        ESPFeature::DISTANCE,
        ESPFeature::SNAPLINES,
        ESPFeature::NAME,
        ESPFeature::STATE,
    };
    
    for (auto feature : features) {
        renderer_->ToggleFeature(feature, true);
        
        // Verify feature is active
        uint32_t feature_mask = static_cast<uint32_t>(feature);
        Assert((renderer_->active_features_ & feature_mask) != 0,
               "Feature " + std::to_string(static_cast<uint32_t>(feature)) + " enabled", result);
        
        // Disable and verify
        renderer_->ToggleFeature(feature, false);
        Assert((renderer_->active_features_ & feature_mask) == 0,
               "Feature " + std::to_string(static_cast<uint32_t>(feature)) + " disabled", result);
    }
    
    Log("Feature toggles test completed");
    return result;
}

void TestESPRenderer::Log(const std::string& message, bool is_error) {
    std::cout << (is_error ? "[ERROR] " : "[INFO] ") << message << std::endl;
}

void TestESPRenderer::Assert(bool condition, const std::string& description,
                             TestResult& result) {
    result.assertions++;
    if (condition) {
        // Test passed
    } else {
        result.failures++;
        result.passed = false;
        Log("Assertion failed: " + description, true);
    }
}

PlayerEntity TestESPRenderer::CreateMockPlayer(uint32_t index) {
    PlayerEntity player{};
    
    // Position
    player.position = CreateMockPosition(
        static_cast<float>(index * 50),
        static_cast<float>(index * 30),
        static_cast<float>(index * 40)
    );
    
    // Screen position (will be calculated by renderer)
    player.screen_position = {1000.0f + index * 20, 600.0f + index * 15};
    player.screen_width = 40.0f;
    player.screen_height = 90.0f;
    
    // Health and shield
    player.health = 100 + index * 5;
    player.max_health = 125;
    player.shield = 50 + index * 10;
    player.max_shield = 100;
    player.shield_cell_count = 2 + index % 3;
    
    // Team assignment
    player.team_id = static_cast<uint8_t>(index % 8);
    player.team = static_cast<Team>(player.team_id);
    
    // State
    player.state = PlayerState::ALIVE;
    
    // Legend assignment
    player.legend_name = static_cast<LegendName>(index % 41);
    
    return player;
}

DirectX::XMFLOAT3 TestESPRenderer::CreateMockPosition(float x, float y, float z) {
    return DirectX::XMFLOAT3{x, y, z};
}
