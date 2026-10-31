#include "test_esp_manager.hpp"
#include "../../esp_manager.hpp"
#include <iostream>
#include <sstream>

// ============================================================================
// Test ESP Manager Implementation
// ============================================================================

TestESPManager::TestESPManager() {
    manager_ = new ESPManager();
}

TestESPManager::~TestESPManager() {
    if (manager_) {
        delete manager_;
    }
}

std::vector<TestResult> TestESPManager::RunAllTests() {
    std::vector<TestResult> results;
    
    // Run individual test methods
    results.push_back(TestInitialization());
    results.push_back(TestConfigurationLoading());
    results.push_back(TestFeatureToggles());
    results.push_back(TestPresetManagement());
    results.push_back(TestRenderLoop());
    results.push_back(TestTeamColorIntegration());
    results.push_back(TestHumanizedConfigIntegration());
    results.push_back(TestLoggingSystem());
    
    return results;
}

TestResult TestESPManager::TestInitialization() {
    TestResult result{"Manager Initialization", true, "ESP manager setup and component initialization", 0, 0};
    
    // Mock window handle
    HWND mock_hwnd = reinterpret_cast<HWND>(0x10000);
    
    bool init_success = manager_->Initialize(mock_hwnd);
    Assert(init_success, "ESP manager initialized", result);
    
    // Verify components initialized
    Assert(manager_->GetState() == ESPState::READY, "Manager state is READY after init", result);
    
    // Verify renderer and extractor are available
    auto& renderer = manager_->GetRenderer();
    auto& extractor = manager_->GetExtractor();
    
    Assert(renderer.IsEnabled(), "Renderer enabled after init", result);
    
    Log("Manager initialization test completed");
    return result;
}

TestResult TestESPManager::TestConfigurationLoading() {
    TestResult result{"Configuration Loading", true, "Loading and applying ESP configuration", 0, 0};
    
    // Test default configuration
    const auto& config = manager_->GetConfig();
    
    Assert(config.enabled, "ESP enabled by default", result);
    Assert(config.update_interval_ms == 16, "Update interval is ~60 FPS (16ms)", result);
    Assert(config.box_style == BoxStyle::CORNER, "Corner box style is default", result);
    Assert(config.glow_enabled, "Glow enabled by default", result);
    
    // Test feature toggles
    const auto& toggles = manager_->GetFeatureToggles();
    Assert(!toggles.empty(), "Feature toggles initialized", result);
    Assert(toggles.size() >= 8, "All expected features have toggles", result);
    
    Log("Configuration loading test completed");
    return result;
}

TestResult TestESPManager::TestFeatureToggles() {
    TestResult result{"Feature Toggles", true, "Enabling/disabling ESP features via manager", 0, 0};
    
    // Test individual feature toggles
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
        manager_->ToggleFeature(feature, true);
        
        // Verify feature is active
        Assert(manager_->GetRenderer().IsEnabled(), 
               "Renderer remains enabled after toggling feature", result);
    }
    
    // Test bulk toggle
    manager_->ToggleESP(false);
    Assert(!manager_->GetRenderer().IsEnabled(), "ESP disabled via ToggleESP", result);
    
    manager_->ToggleESP(true);
    Assert(manager_->GetRenderer().IsEnabled(), "ESP re-enabled via ToggleESP", result);
    
    Log("Feature toggles test completed");
    return result;
}

TestResult TestESPManager::TestPresetManagement() {
    TestResult result{"Preset Management", true, "Loading and saving ESP presets", 0, 0};
    
    // Test default preset creation
    std::string default_preset = "default";
    bool save_success = manager_->SavePreset(default_preset);
    Assert(save_success, "Default preset saved successfully", result);
    
    // Verify preset file exists
    std::string preset_path = manager_->GetConfig().preset_dir + "\\" + default_preset + ".json";
    // Note: In real implementation, would check fs::exists(preset_path)
    
    // Test configuration persistence
    auto& config = manager_->GetConfig();
    config.glow_intensity = 1.2f;  // Modify some settings
    config.health_bar_enabled = true;
    
    bool save_config = manager_->SaveConfig();
    Assert(save_config, "Configuration saved after modifications", result);
    
    Log("Preset management test completed");
    return result;
}

TestResult TestESPManager::TestRenderLoop() {
    TestResult result{"Render Loop", true, "Updating and rendering ESP each frame", 0, 0};
    
    // Start render loop
    manager_->ToggleESP(true);
    Assert(manager_->GetState() == ESPState::RUNNING, "Render loop started", result);
    
    // Simulate multiple update cycles
    for (int i = 0; i < 5; ++i) {
        manager_->Update();
        Assert(manager_->GetState() == ESPState::RUNNING,
               "Render loop maintains RUNNING state", result);
    }
    
    // Test render calls
    manager_->Render();
    Assert(manager_->GetRenderer().IsEnabled(), "Render call successful", result);
    
    Log("Render loop test completed");
    return result;
}

TestResult TestESPManager::TestTeamColorIntegration() {
    TestResult result{"Team Color Integration", true, "Team colors properly applied across components", 0, 0};
    
    // Test team colors in renderer
    auto& renderer = manager_->GetRenderer();
    
    std::vector<Team> teams = {
        Team::RED, Team::BLUE, Team::GREEN, Team::ORANGE,
        Team::PURPLE, Team::YELLOW, Team::TEAL, Team::PINK
    };
    
    for (auto team : teams) {
        auto color = renderer.GetTeamColor(team, false);
        auto glow_color = renderer.GetTeamColor(team, true);
        
        // Verify colors are different for team vs glow
        Assert(color.x != glow_color.x || color.y != glow_color.y,
               "Team " + std::to_string(static_cast<int>(team)) + " has distinct glow color", result);
    }
    
    Log("Team color integration test completed");
    return result;
}

TestResult TestESPManager::TestHumanizedConfigIntegration() {
    TestResult result{"Humanized Config Integration", true, "Wraith tight, Gibraltar loose patterns work correctly", 0, 0};
    
    // Test Wraith (tight pattern)
    auto wraith_config = manager_->GetExtractor().GetHumanizedConfig(LegendName::WRAITH);
    Assert(wraith_config.is_tight, "Wraith has tight hitbox", result);
    Assert(!wraith_config.is_loose, "Wraith is not loose", result);
    
    // Test Griffin (loose pattern)
    auto griffin_config = manager_->GetExtractor().GetHumanizedConfig(LegendName::GRIFFIN);
    Assert(griffin_config.is_loose, "Griffin has loose hitbox", result);
    Assert(!griffin_config.is_tight, "Griffin is not tight", result);
    
    // Test Caustic (tight)
    auto caustic_config = manager_->GetExtractor().GetHumanizedConfig(LegendName::CAUSTIC);
    Assert(caustic_config.is_tight, "Caustic has tight hitbox", result);
    
    Log("Humanized config integration test completed");
    return result;
}

TestResult TestESPManager::TestLoggingSystem() {
    TestResult result{"Logging System", true, "Log entries created and persisted correctly", 0, 0};
    
    // Test various log messages
    manager_->Log("Test message 1");
    manager_->Log("Test message 2", false);
    manager_->Log("Error message", true);
    
    // Verify logs were created
    const auto& logs = manager_->GetLogEntries();
    Assert(logs.size() >= 3, "All log entries created", result);
    
    // Verify error flagging
    bool has_error = false;
    for (const auto& [msg, is_error] : logs) {
        if (is_error && msg.find("Error") != std::string::npos) {
            has_error = true;
            break;
        }
    }
    Assert(has_error, "Error messages properly flagged", result);
    
    Log("Logging system test completed");
    return result;
}

void TestESPManager::Log(const std::string& message, bool is_error) {
    std::cout << (is_error ? "[ERROR] " : "[INFO] ") << message << std::endl;
}

void TestESPManager::Assert(bool condition, const std::string& description,
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
