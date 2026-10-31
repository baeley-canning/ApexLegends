#include "config.h"
#include <fstream>
#include <sstream>
#include <iostream>
#include <algorithm>
#include <cctype>

ConfigManager::ConfigManager(const std::string& path) : configPath(path) {
}

bool ConfigManager::LoadConfig() {
    std::ifstream file(configPath);
    if (!file.is_open()) {
        // Create default configuration
        SaveConfig();
        return false;
    }
    
    std::string line;
    while (std::getline(file, line)) {
        // Skip empty lines and comments
        if (line.empty() || line[0] == '#' || line[0] == ';') {
            continue;
        }
        
        size_t delimiterPos = line.find('=');
        if (delimiterPos != std::string::npos) {
            std::string key = line.substr(0, delimiterPos);
            std::string value = line.substr(delimiterPos + 1);
            
            // Trim whitespace from key and value
            key.erase(key.begin(), std::find_if(key.begin(), key.end(), [](unsigned char ch) {
                return !std::isspace(ch);
            }));
            key.erase(std::find_if(key.rbegin(), key.rend(), [](unsigned char ch) {
                return !std::isspace(ch);
            }).base(), key.end());
            
            value.erase(value.begin(), std::find_if(value.begin(), value.end(), [](unsigned char ch) {
                return !std::isspace(ch);
            }));
            value.erase(std::find_if(value.rbegin(), value.rend(), [](unsigned char ch) {
                return !std::isspace(ch);
            }).base(), value.end());
            
            configValues[key] = value;
        }
    }
    
    file.close();
    return true;
}

bool ConfigManager::SaveConfig() {
    std::ofstream file(configPath);
    if (!file.is_open()) {
        return false;
    }
    
    // Write configuration values
    for (const auto& pair : configValues) {
        file << pair.first << "=" << pair.second << "\n";
    }
    
    file.close();
    return true;
}

bool ConfigManager::GetBoolValue(const std::string& key, bool defaultValue) {
    auto it = configValues.find(key);
    if (it != configValues.end()) {
        std::string value = it->second;
        // Convert to lowercase for comparison.
        // ::tolower is int(int) from <ctype.h>, so the functor must narrow
        // explicitly: assigning int back through the string iterator is C4244
        // under /W4 (/WX makes it fatal).  unsigned char first, so no UB on
        // bytes >= 0x80 (locales with negative char indexes).
        std::transform(value.begin(), value.end(), value.begin(),
                       [](unsigned char ch) {
                           return static_cast<char>(std::tolower(ch));
                       });
        return (value == "true" || value == "1");
    }
    return defaultValue;
}

int ConfigManager::GetIntValue(const std::string& key, int defaultValue) {
    auto it = configValues.find(key);
    if (it != configValues.end()) {
        try {
            return std::stoi(it->second);
        } catch (...) {
            return defaultValue;
        }
    }
    return defaultValue;
}

float ConfigManager::GetFloatValue(const std::string& key, float defaultValue) {
    auto it = configValues.find(key);
    if (it != configValues.end()) {
        try {
            return std::stof(it->second);
        } catch (...) {
            return defaultValue;
        }
    }
    return defaultValue;
}

std::string ConfigManager::GetStringValue(const std::string& key, const std::string& defaultValue) {
    auto it = configValues.find(key);
    if (it != configValues.end()) {
        return it->second;
    }
    return defaultValue;
}

void ConfigManager::SetBoolValue(const std::string& key, bool value) {
    SetStringValue(key, value ? "true" : "false");
}

void ConfigManager::SetIntValue(const std::string& key, int value) {
    SetStringValue(key, std::to_string(value));
}

void ConfigManager::SetFloatValue(const std::string& key, float value) {
    SetStringValue(key, std::to_string(value));
}

void ConfigManager::SetStringValue(const std::string& key, const std::string& value) {
    configValues[key] = value;
}