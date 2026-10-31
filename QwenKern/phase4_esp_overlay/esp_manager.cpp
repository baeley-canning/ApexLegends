#include "esp_manager.hpp"
#include "esp_renderer.hpp"
#include "entity_extractor.hpp"
#include <fstream>
#include <sstream>
#include <chrono>
#include <iomanip>
#include <filesystem>

namespace fs = std::filesystem;

// ============================================================================
// ESP Manager Implementation
// ============================================================================

ESPManager::ESPManager() {
    renderer_ = std::make_unique<ESPRenderer>();
    extractor_ = std::make_unique<EntityExtractor>();
}

ESPManager::~ESPManager() {
    Shutdown();
}

bool ESPManager::Initialize(HWND game_hwnd) {
    if (!game_hwnd) {
        return false;
    }
    
    game_hwnd_ = game_hwnd;
    state_ = ESPState::INITIALIZING;
    
    // Set up paths
    paths_.config_dir = "C:\\Users\\New User\\OneDrive\\Desktop\\QwenKern\\phase4_esp_overlay\\configs";
    paths_.config_file = paths_.config_dir + "\\esp_config.json";
    paths_.preset_dir = paths_.config_dir + "\\presets";
    paths_.log_file = paths_.config_dir + "\\esp_log.txt";
    
    // Create directories if they don't exist
    try {
        fs::create_directories(paths_.config_dir);
        fs::create_directories(paths_.preset_dir);
    } catch (const std::exception& e) {
        LogInternal(std::string("Failed to create ESP directories: ") + e.what(), true);
    }
    
    // Initialize entity extractor
    HMODULE game_module = nullptr;
    GetModuleHandleEx(GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                      L"ApexLegends.exe", &game_module);
    
    if (extractor_->Initialize(game_module)) {
        LogInternal("Entity extractor initialized successfully");
    } else {
        LogInternal("Failed to initialize entity extractor", true);
    }
    
    // Initialize renderer
    if (renderer_->Initialize(game_hwnd)) {
        LogInternal("ESP renderer initialized successfully");
    } else {
        LogInternal("Failed to initialize ESP renderer", true);
    }
    
    // Load configuration
    LoadConfig();
    
    // Initialize feature toggles
    InitializeFeatureToggles();
    
    state_ = ESPState::READY;
    LogInternal("ESP manager initialization complete");
    
    return true;
}

void ESPManager::Shutdown() {
    if (state_ == ESPState::SHUTDOWN) {
        return;
    }
    
    state_ = ESPState::PAUSED;
    
    // Save current configuration
    SaveConfig();
    
    // Shutdown renderer
    renderer_->Shutdown();
    
    // Shutdown extractor
    // (EntityExtractor doesn't have explicit shutdown)
    
    state_ = ESPState::SHUTDOWN;
    LogInternal("ESP manager shutdown complete");
}

void ESPManager::Update() {
    if (state_ != ESPState::RUNNING) {
        return;
    }
    
    auto now = std::chrono::high_resolution_clock::now();
    uint64_t current_time = std::chrono::duration_cast<std::chrono::milliseconds>(
        now.time_since_epoch()).count();
    
    // Update at configured interval
    if (current_time - last_update_time_ >= config_.update_interval_ms) {
        last_update_time_ = current_time;
        
        // Extract entities
        auto entities = extractor_->ExtractEntities();
        
        // Update local player reference
        if (entities.local_player) {
            entities.local_player->is_local_player = true;
        }
        
        // Render ESP
        renderer_->Render(entities.players, *extractor_, config_);
    }
}

void ESPManager::Render() {
    if (state_ != ESPState::RUNNING && state_ != ESPState::PAUSED) {
        return;
    }
    
    auto entities = extractor_->ExtractEntities();
    renderer_->Render(entities.players, *extractor_, config_);
}

void ESPManager::ToggleESP(bool enabled) {
    renderer_->SetEnabled(enabled);
    
    if (enabled && state_ == ESPState::READY) {
        state_ = ESPState::RUNNING;
        LogInternal("ESP enabled");
    } else if (!enabled && state_ == ESPState::RUNNING) {
        state_ = ESPState::PAUSED;
        LogInternal("ESP paused");
    }
    
    // Update feature toggles to reflect new state
    for (auto& toggle : feature_toggles_) {
        if ((toggle.feature == ESPFeature::BOX || 
             toggle.feature == ESPFeature::GLOW ||
             toggle.feature == ESPFeature::SKELETON) && 
            !enabled) {
            toggle.enabled = false;
            if (toggle.callback) {
                toggle.callback(false);
            }
        }
    }
}

void ESPManager::ToggleFeature(ESPFeature feature, bool enabled) {
    renderer_->ToggleFeature(feature, enabled);
    
    // Update feature toggle state
    for (auto& toggle : feature_toggles_) {
        if (toggle.feature == feature) {
            toggle.enabled = enabled;
            if (toggle.callback) {
                toggle.callback(enabled);
            }
        }
    }
    
    std::ostringstream oss;
    oss << "Feature '" << static_cast<uint32_t>(feature) 
        << "' " << (enabled ? "enabled" : "disabled");
    LogInternal(oss.str());
}

bool ESPManager::LoadConfig(const std::string& config_path) {
    std::string path = config_path.empty() ? paths_.config_file : config_path;
    
    if (!fs::exists(path)) {
        LogInternal("Config file not found, using defaults: " + path);
        return true;
    }
    
    try {
        auto loaded_config = ESPConfigLoader::LoadConfigFromFile(path);
        config_ = loaded_config;
        
        // Apply configuration to renderer
        renderer_->UpdateConfig(config_);
        
        LogInternal("Configuration loaded from: " + path);
        return true;
    } catch (const std::exception& e) {
        LogInternal(std::string("Failed to load config: ") + e.what(), true);
        return false;
    }
}

bool ESPManager::SaveConfig(const std::string& config_path) {
    std::string path = config_path.empty() ? paths_.config_file : config_path;
    
    try {
        ESPConfigLoader::SaveConfigToFile(config_, path);
        LogInternal("Configuration saved to: " + path);
        return true;
    } catch (const std::exception& e) {
        LogInternal(std::string("Failed to save config: ") + e.what(), true);
        return false;
    }
}

bool ESPManager::LoadPreset(const std::string& preset_name) {
    std::string path = paths_.preset_dir + "\\" + preset_name + ".json";
    
    if (!fs::exists(path)) {
        LogInternal("Preset not found: " + preset_name, true);
        return false;
    }
    
    try {
        auto preset_config = ESPConfigLoader::LoadPresetFromFile(path);
        config_ = preset_config;
        
        // Apply configuration to renderer
        renderer_->UpdateConfig(config_);
        
        LogInternal("Preset '" + preset_name + "' loaded");
        return true;
    } catch (const std::exception& e) {
        LogInternal(std::string("Failed to load preset: ") + e.what(), true);
        return false;
    }
}

bool ESPManager::SavePreset(const std::string& preset_name) {
    std::string path = paths_.preset_dir + "\\" + preset_name + ".json";
    
    try {
        ESPConfigLoader::SavePresetToFile(config_, path);
        LogInternal("Preset '" + preset_name + "' saved");
        return true;
    } catch (const std::exception& e) {
        LogInternal(std::string("Failed to save preset: ") + e.what(), true);
        return false;
    }
}

void ESPManager::AddFeatureToggle(const FeatureToggle& toggle) {
    feature_toggles_.push_back(toggle);
}

void ESPManager::Log(const std::string& message, bool is_error) {
    LogInternal(message, is_error);
}

void ESPManager::InitializeFeatureToggles() {
    feature_toggles_ = {
        {"Box", "Enable/disable box rendering around players", 
         ESPFeature::BOX, true, [this](bool e) { ToggleFeature(ESPFeature::BOX, e); }},
        {"Glow", "Enable/disable glow effects around boxes",
         ESPFeature::GLOW, true, [this](bool e) { ToggleFeature(ESPFeature::GLOW, e); }},
        {"Skeleton", "Enable/disable skeleton bone rendering",
         ESPFeature::SKELETON, true, [this](bool e) { ToggleFeature(ESPFeature::SKELETON, e); }},
        {"Health Bar", "Enable/disable health and shield bars",
         ESPFeature::HEALTH_BAR, true, [this](bool e) { ToggleFeature(ESPFeature::HEALTH_BAR, e); }},
        {"Distance", "Enable/disable distance indicators",
         ESPFeature::DISTANCE, true, [this](bool e) { ToggleFeature(ESPFeature::DISTANCE, e); }},
        {"Snaplines", "Enable/disable snaplines from center screen",
         ESPFeature::SNAPLINES, true, [this](bool e) { ToggleFeature(ESPFeature::SNAPLINES, e); }},
        {"Name", "Enable/disable player and legend names",
         ESPFeature::NAME, true, [this](bool e) { ToggleFeature(ESPFeature::NAME, e); }},
        {"State", "Enable/disable player state indicators (ALIVE/DEAD)",
         ESPFeature::STATE, true, [this](bool e) { ToggleFeature(ESPFeature::STATE, e); }},
    };
}

void ESPManager::LogInternal(const std::string& message, bool is_error) {
    auto now = std::chrono::system_clock::now();
    auto time_t_now = std::chrono::system_clock::to_time_t(now);
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        now.time_since_epoch()) % 1000;
    
    std::ostringstream oss;
    oss << std::put_time(std::localtime(&time_t_now), "%Y-%m-%d %H:%M:%S");
    oss << '.' << std::setfill('0') << std::setw(3) << ms.count();
    
    std::string timestamp = oss.str();
    std::string log_entry = "[" + timestamp + "] " + message;
    
    if (is_error) {
        log_entry = "[ERROR] " + log_entry;
    }
    
    log_entries_.emplace_back(log_entry, is_error);
    
    // Also write to log file
    try {
        std::ofstream log_file(paths_.log_file, std::ios::app);
        if (log_file.is_open()) {
            log_file << log_entry << "\n";
        }
    } catch (const std::exception& e) {
        // Silently handle log file errors
    }
}

// ============================================================================
// ESP Config Loader Implementation
// ============================================================================

bool ESPConfigLoader::SaveConfigToFile(const ESPConfig& config, const std::string& filepath) {
    std::ofstream file(filepath);
    if (!file.is_open()) {
        return false;
    }
    
    file << "{\n";
    file << "  \"enabled\": " << (config.enabled ? "true" : "false") << ",\n";
    file << "  \"update_interval_ms\": " << config.update_interval_ms << ",\n";
    file << "  \"box_style\": " << static_cast<int>(config.box_style) << ",\n";
    file << "  \"box_padding\": " << config.box_padding << ",\n";
    file << "  \"corner_size\": " << config.corner_size << ",\n";
    file << "  \"line_thickness\": " << config.line_thickness << ",\n";
    file << "  \"glow_enabled\": " << (config.glow_enabled ? "true" : "false") << ",\n";
    file << "  \"glow_intensity\": " << config.glow_intensity << ",\n";
    file << "  \"glow_thickness\": " << config.glow_thickness << ",\n";
    file << "  \"dynamic_glow\": " << (config.dynamic_glow ? "true" : "false") << ",\n";
    file << "  \"skeleton_enabled\": " << (config.skeleton_enabled ? "true" : "false") << ",\n";
    file << "  \"bone_size\": " << config.bone_size << ",\n";
    file << "  \"health_bar_enabled\": " << (config.health_bar_enabled ? "true" : "false") << ",\n";
    file << "  \"health_bar_width\": " << config.health_bar_width << ",\n";
    file << "  \"health_bar_height\": " << config.health_bar_height << ",\n";
    file << "  \"show_shield_bar\": " << (config.show_shield_bar ? "true" : "false") << ",\n";
    file << "  \"distance_enabled\": " << (config.distance_enabled ? "true" : "false") << ",\n";
    file << "  \"show_distance_in_units\": " << (config.show_distance_in_units ? "true" : "false") << ",\n";
    file << "  \"snaplines_enabled\": " << (config.snaplines_enabled ? "true" : "false") << ",\n";
    file << "  \"snapline_color\": ["
         << config.snapline_color.x << ", "
         << config.snapline_color.y << ", "
         << config.snapline_color.z << "],\n";
    file << "  \"text_size\": " << config.text_size << ",\n";
    file << "  \"shadow_text\": " << (config.shadow_text ? "true" : "false") << ",\n";
    file << "  \"team_colors_enabled\": " << (config.team_colors_enabled ? "true" : "false") << ",\n";
    file << "  \"use_glow_colors\": " << (config.use_glow_colors ? "true" : "false") << ",\n";
    file << "  \"humanized_features_enabled\": " << (config.humanized_features_enabled ? "true" : "false") << "\n";
    file << "}\n";
    
    return true;
}

ESPConfig ESPConfigLoader::LoadConfigFromFile(const std::string& filepath) {
    ESPConfig config{};
    
    // Read file and parse JSON-like format
    std::ifstream file(filepath);
    if (!file.is_open()) {
        return CreateDefaultConfig();
    }
    
    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string content = buffer.str();
    
    // Parse common fields (simplified JSON parsing)
    auto parse_value = [&](const std::string& key, bool is_bool = false) -> std::string {
        size_t pos = content.find(key);
        if (pos == std::string::npos) return "";
        
        pos = content.find(':', pos);
        if (pos == std::string::npos) return "";
        
        pos++;
        // Skip whitespace
        while (pos < content.size() && (content[pos] == ' ' || content[pos] == '\t' || content[pos] == '\n')) {
            pos++;
        }
        
        // Find value
        size_t start = pos;
        if (is_bool) {
            // Boolean value
            if (content.substr(pos, 4) == "true") return "true";
            if (content.substr(pos, 5) == "false") return "false";
            return "";
        } else {
            // Numeric or string value
            char quote = '"';
            if (content[pos] == quote) {
                start = pos + 1;
                size_t end = content.find(quote, start);
                return content.substr(start, end - start);
            } else {
                size_t end = pos;
                while (end < content.size() && 
                       (isdigit(content[end]) || content[end] == '.' || content[end] == '-')) {
                    end++;
                }
                return content.substr(pos, end - pos);
            }
        }
    };
    
    config.enabled = parse_value("enabled", true) == "true";
    config.update_interval_ms = std::stoul(parse_value("update_interval_ms"));
    config.box_style = static_cast<BoxStyle>(std::stoul(parse_value("box_style")));
    config.box_padding = std::stof(parse_value("box_padding"));
    config.corner_size = std::stof(parse_value("corner_size"));
    config.line_thickness = std::stof(parse_value("line_thickness"));
    config.glow_enabled = parse_value("glow_enabled", true) == "true";
    config.glow_intensity = std::stof(parse_value("glow_intensity"));
    config.glow_thickness = std::stof(parse_value("glow_thickness"));
    config.dynamic_glow = parse_value("dynamic_glow", true) == "true";
    config.skeleton_enabled = parse_value("skeleton_enabled", true) == "true";
    config.bone_size = std::stof(parse_value("bone_size"));
    config.health_bar_enabled = parse_value("health_bar_enabled", true) == "true";
    config.health_bar_width = std::stof(parse_value("health_bar_width"));
    config.health_bar_height = std::stof(parse_value("health_bar_height"));
    config.show_shield_bar = parse_value("show_shield_bar", true) == "true";
    config.distance_enabled = parse_value("distance_enabled", true) == "true";
    config.show_distance_in_units = parse_value("show_distance_in_units", true) == "true";
    config.snaplines_enabled = parse_value("snaplines_enabled", true) == "true";
    config.text_size = std::stof(parse_value("text_size"));
    config.shadow_text = parse_value("shadow_text", true) == "true";
    config.team_colors_enabled = parse_value("team_colors_enabled", true) == "true";
    config.use_glow_colors = parse_value("use_glow_colors", true) == "true";
    config.humanized_features_enabled = parse_value("humanized_features_enabled", true) == "true";
    
    return config;
}

bool ESPConfigLoader::SavePresetToFile(const ESPConfig& config, const std::string& filepath) {
    // Add preset header
    std::ofstream file(filepath);
    if (!file.is_open()) {
        return false;
    }
    
    file << "// ESP Preset - " << filepath << "\n";
    file << "// Generated: " << __DATE__ << " " << __TIME__ << "\n\n";
    
    // Reuse config saving logic
    return SaveConfigToFile(config, filepath);
}

ESPConfig ESPConfigLoader::LoadPresetFromFile(const std::string& filepath) {
    ESPConfig config = LoadConfigFromFile(filepath);
    
    // Add preset-specific defaults if needed
    config.enabled = true;
    
    return config;
}

std::vector<std::string> ESPConfigLoader::GetAvailablePresets(const std::string& preset_dir) {
    std::vector<std::string> presets;
    
    try {
        for (const auto& entry : fs::directory_iterator(preset_dir)) {
            if (entry.is_regular_file() && entry.path().extension() == ".json") {
                presets.push_back(entry.path().stem().string());
            }
        }
    } catch (const std::exception& e) {
        // Return empty vector on error
    }
    
    return presets;
}

ESPConfig ESPConfigLoader::CreateDefaultConfig() {
    ESPConfig config{};
    
    config.enabled = true;
    config.update_interval_ms = 16;  // ~60 FPS
    
    // Box settings
    config.box_style = BoxStyle::CORNER;
    config.box_padding = 4.0f;
    config.corner_size = 8.0f;
    config.line_thickness = 1.5f;
    
    // Glow settings
    config.glow_enabled = true;
    config.glow_intensity = 0.8f;
    config.glow_thickness = 2.0f;
    config.dynamic_glow = true;
    
    // Skeleton settings
    config.skeleton_enabled = true;
    config.bone_size = 2.0f;
    
    // Health bar settings
    config.health_bar_enabled = true;
    config.health_bar_width = 3.0f;
    config.health_bar_height = 40.0f;
    config.show_shield_bar = true;
    
    // Distance settings
    config.distance_enabled = true;
    config.show_distance_in_units = false;
    
    // Snapline settings
    config.snaplines_enabled = true;
    config.snapline_color = {0.5f, 0.5f, 0.5f};
    
    // Text settings
    config.text_size = 12.0f;
    config.shadow_text = true;
    
    // Team colors
    config.team_colors_enabled = true;
    config.use_glow_colors = true;
    
    // Humanized features
    config.humanized_features_enabled = true;
    
    return config;
}
