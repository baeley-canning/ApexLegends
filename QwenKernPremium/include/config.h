#pragma once
#include <string>
#include <map>

class ConfigManager {
private:
    std::string configPath;
    
public:
    ConfigManager(const std::string& path = "config.ini");
    ~ConfigManager() = default;
    
    // Load configuration from file
    bool LoadConfig();
    
    // Save configuration to file
    bool SaveConfig();
    
    // Get configuration values
    bool GetBoolValue(const std::string& key, bool defaultValue = false);
    int GetIntValue(const std::string& key, int defaultValue = 0);
    float GetFloatValue(const std::string& key, float defaultValue = 0.0f);
    std::string GetStringValue(const std::string& key, const std::string& defaultValue = "");
    
    // Set configuration values
    void SetBoolValue(const std::string& key, bool value);
    void SetIntValue(const std::string& key, int value);
    void SetFloatValue(const std::string& key, float value);
    void SetStringValue(const std::string& key, const std::string& value);

    // PHASE 1 / T4 (ov-series): write the seven feature toggles to the ini.
    // Called by the overlay menu on every change so the file always matches the
    // live state.  Keys: aimbot, esp, glow, recoil, esp_boxes, esp_names,
    // esp_lines - the first four are exactly what Application::LoadConfiguration
    // reads back at startup.
    bool FlushFeatureToggles(bool aimbot, bool esp, bool glow, bool recoil,
                            bool espBoxes, bool espNames, bool espLines);
    
private:
    std::map<std::string, std::string> configValues;
};

// Process-wide ConfigManager used by the menu write path (d3d12_overlay.cpp).
// Application keeps its own instance that only READS at init; this singleton
// owns every later write, so the file always has exactly one writer.  It is
// deliberately heap-allocated and never deleted: in the manually-mapped payload
// the CRT teardown is not guaranteed to run, and a static object's destructor
// firing during module unload is the riskier failure mode.
ConfigManager* SharedMenuConfig();