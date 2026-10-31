#pragma once
#ifndef ESP_MANAGER_HPP
#define ESP_MANAGER_HPP

#include <Windows.h>
#include <string>
#include <vector>
#include <functional>
#include <memory>

// Forward declarations
struct ESPConfig;
class ESPRenderer;
class EntityExtractor;

// ESP manager configuration paths
struct ESPPaths {
    std::string config_dir;
    std::string config_file;
    std::string preset_dir;
    std::string log_file;
};

// ESP manager state enumeration
enum class ESPState : uint8_t {
    INITIALIZING = 0,
    READY = 1,
    RUNNING = 2,
    PAUSED = 3,
    SHUTDOWN = 4,
};

// Feature toggle structure for easy UI binding
struct FeatureToggle {
    std::string name;
    std::string description;
    ESPFeature feature;
    bool enabled;
    std::function<void(bool)> callback;
};

// ESP manager class for controlling the overlay system
class ESPManager {
public:
    ESPManager();
    ~ESPManager();
    
    // Initialize ESP system
    bool Initialize(HWND game_hwnd);
    
    // Shutdown ESP system
    void Shutdown();
    
    // Update ESP (called each frame)
    void Update();
    
    // Render ESP
    void Render();
    
    // Toggle ESP on/off
    void ToggleESP(bool enabled);
    
    // Toggle specific feature
    void ToggleFeature(ESPFeature feature, bool enabled = true);
    
    // Load configuration from file
    bool LoadConfig(const std::string& config_path = "");
    
    // Save configuration to file
    bool SaveConfig(const std::string& config_path = "");
    
    // Load preset configuration
    bool LoadPreset(const std::string& preset_name);
    
    // Save current config as preset
    bool SavePreset(const std::string& preset_name);
    
    // Get current state
    ESPState GetState() const { return state_; }
    
    // Get configuration
    ESPConfig& GetConfig() { return config_; }
    const ESPConfig& GetConfig() const { return config_; }
    
    // Get renderer reference
    ESPRenderer& GetRenderer() { return *renderer_; }
    const ESPRenderer& GetRenderer() const { return *renderer_; }
    
    // Get entity extractor reference
    EntityExtractor& GetExtractor() { return *extractor_; }
    const EntityExtractor& GetExtractor() const { return *extractor_; }
    
    // Add feature toggle for UI
    void AddFeatureToggle(const FeatureToggle& toggle);
    
    // Get all feature toggles
    const std::vector<FeatureToggle>& GetFeatureToggles() const { return feature_toggles_; }
    
    // Log message with timestamp
    void Log(const std::string& message, bool is_error = false);
    
    // Get log entries
    const std::vector<std::pair<std::string, bool>>& GetLogEntries() const { return log_entries_; }

private:
    // ESP state
    ESPState state_ = ESPState::INITIALIZING;
    
    // Components
    std::unique_ptr<ESPRenderer> renderer_;
    std::unique_ptr<EntityExtractor> extractor_;
    
    // Configuration
    ESPConfig config_;
    ESPPaths paths_;
    
    // Feature toggles for UI
    std::vector<FeatureToggle> feature_toggles_;
    
    // Log entries
    std::vector<std::pair<std::string, bool>> log_entries_;
    
    // Last update time
    uint64_t last_update_time_ = 0;
    
    // Game window handle
    HWND game_hwnd_ = nullptr;
    
    // Helper methods
    void InitializeFeatureToggles();
    void LogInternal(const std::string& message, bool is_error);
};

// Configuration loader/saver helper class
class ESPConfigLoader {
public:
    // Save ESP configuration to JSON-like format
    static bool SaveConfigToFile(const ESPConfig& config, const std::string& filepath);
    
    // Load ESP configuration from file
    static ESPConfig LoadConfigFromFile(const std::string& filepath);
    
    // Save preset configuration
    static bool SavePresetToFile(const ESPConfig& config, const std::string& filepath);
    
    // Load preset configuration
    static ESPConfig LoadPresetFromFile(const std::string& filepath);
    
    // Get list of available presets
    static std::vector<std::string> GetAvailablePresets(const std::string& preset_dir);
    
    // Default configuration factory
    static ESPConfig CreateDefaultConfig();
};

#endif // ESP_MANAGER_HPP
