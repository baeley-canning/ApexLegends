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
    
private:
    std::map<std::string, std::string> configValues;
};