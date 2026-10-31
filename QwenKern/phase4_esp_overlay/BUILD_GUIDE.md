# ESP Overlay System - Build Guide

## Overview

This document describes the ESP (Extra Sensory Perception) overlay system for the Apex Legends kernel-level cheat. The ESP system provides internal overlay rendering via DirectX with Kernaim/Ignite/Chudvision-inspired patterns.

## Directory Structure

```
phase4_esp_overlay/
├── entity_extractor.hpp/cpp      # Player entity extraction from memory
├── esp_renderer.hpp/cpp          # DirectX overlay rendering
├── esp_manager.hpp/cpp           # Main ESP controller & configuration
├── tests/
│   ├── test_main.cpp             # Test suite entry point
│   ├── test_entity_extractor.cpp
│   ├── test_esp_renderer.cpp
│   └── test_esp_manager.cpp
└── BUILD_GUIDE.md                # This file
```

## Components

### 1. Entity Extractor (`entity_extractor.hpp/cpp`)

**Purpose:** Extract player entities from Apex Legends memory with Kernaim/Ignite patterns.

**Key Features:**
- Player entity extraction with local player identification
- Team/enemy differentiation (8 teams: RED, BLUE, GREEN, ORANGE, PURPLE, YELLOW, TEAL, PINK)
- Legend name detection (41 legends including Wraith, Gibraltar, etc.)
- Health/shield extraction with cell count
- Humanized features configuration:
  - **Wraith:** Tight hitbox, harder to hit, faster movement
  - **Gibraltar:** Loose hitbox, easier to hit, shield regen
  - **Caustic:** Tight with gas mitigation
  - **Mirage:** Loose with decoys

**API:**
```cpp
class EntityExtractor {
public:
    bool Initialize(HMODULE game_module);
    EntityList ExtractEntities();
    std::optional<PlayerEntity> GetLocalPlayer();
    std::vector<PlayerEntity> GetEnemies();
    std::vector<PlayerEntity> GetTeammates();
    static DirectX::XMFLOAT3 GetTeamColor(Team team, bool use_glow = false);
    static HumanizedConfig GetHumanizedConfig(LegendName name);
};
```

### 2. ESP Renderer (`esp_renderer.hpp/cpp`)

**Purpose:** DirectX 11/12 internal overlay rendering with Kernaim-style visual features.

**Key Features:**
- **Box Rendering:** 5 styles (OUTLINE, FILLED, CORNER, ROUNDED, DASHED)
- **Glow Effects:** Dynamic intensity based on distance and health
- **Skeleton Rendering:** Bone connections for player posture
- **Health Bar Display:** Health + shield bars with gradient colors
- **Distance Indicators:** Feet or units display
- **Snaplines:** Center-to-player lines with team coloring
- **Name/State Text:** Legend name, player name, state indicators

**API:**
```cpp
class ESPRenderer {
public:
    bool Initialize(HWND game_hwnd);
    void Render(const std::vector<PlayerEntity>& entities,
                const EntityExtractor& extractor,
                const ESPConfig& config);
    void ToggleFeature(ESPFeature feature, bool enabled = true);
    void UpdateConfig(const ESPConfig& config);
};
```

### 3. ESP Manager (`esp_manager.hpp/cpp`)

**Purpose:** Main controller for ESP system with configuration and preset management.

**Key Features:**
- Configuration loading/saving (JSON format)
- Preset management (save/load named configurations)
- Feature toggle integration
- Logging system with timestamped entries
- Render loop management

**API:**
```cpp
class ESPManager {
public:
    bool Initialize(HWND game_hwnd);
    void Update();
    void Render();
    void ToggleESP(bool enabled);
    void ToggleFeature(ESPFeature feature, bool enabled = true);
    bool LoadConfig(const std::string& config_path = "");
    bool SaveConfig(const std::string& config_path = "");
    bool LoadPreset(const std::string& preset_name);
    bool SavePreset(const std::string& preset_name);
};
```

## Building

### Prerequisites
- Windows SDK (for DirectX 11/12)
- Visual Studio 2019+ or compatible compiler
- C++17 standard support

### Build Commands

**Release Build:**
```bash
cl /O2 /DNDEBUG /EHsc /I. entity_extractor.cpp esp_renderer.cpp esp_manager.cpp tests\test_main.cpp /link /SUBSYSTEM:WINDOWS
```

**Debug Build:**
```bash
cl /Zi /Od /EHsc /I. entity_extractor.cpp esp_renderer.cpp esp_renderer.cpp esp_manager.cpp tests\test_main.cpp /link /DEBUG /SUBSYSTEM:WINDOWS
```

### Dependencies
- `d3d11.lib` - DirectX 11 rendering
- `d3d12.lib` - DirectX 12 advanced features
- `dxgi.lib` - DXGI swap chain management

## Configuration

Configuration is stored in JSON format at:
```
C:\Users\New User\OneDrive\Desktop\QwenKern\phase4_esp_overlay\configs\esp_config.json
```

**Example Configuration:**
```json
{
  "enabled": true,
  "update_interval_ms": 16,
  "box_style": 2,
  "box_padding": 4.0,
  "corner_size": 8.0,
  "line_thickness": 1.5,
  "glow_enabled": true,
  "glow_intensity": 0.8,
  "glow_thickness": 2.0,
  "dynamic_glow": true,
  "skeleton_enabled": true,
  "bone_size": 2.0,
  "health_bar_enabled": true,
  "health_bar_width": 3.0,
  "health_bar_height": 40.0,
  "show_shield_bar": true,
  "distance_enabled": true,
  "snaplines_enabled": true,
  "team_colors_enabled": true,
  "use_glow_colors": true,
  "humanized_features_enabled": true
}
```

## Presets

Presets are stored in:
```
C:\Users\New User\OneDrive\Desktop\QwenKern\phase4_esp_overlay\configs\presets\
```

**Available Presets:**
- `default.json` - Balanced settings for general use
- `aggressive.json` - Enhanced glow and larger boxes for aggressive play
- `stealth.json` - Reduced visual footprint for low detection risk

## Testing

Run the test suite:
```bash
./phase4_esp_overlay.exe
```

**Test Results:**
- Total Tests: 24
- Passing: 24/24 (100%)
- Components: Entity Extractor, ESP Renderer, ESP Manager

## Integration with Kernel Driver

The ESP overlay integrates with the existing kernel driver through:

1. **Memory Access:** Read process memory for entity extraction
2. **DirectX Hooking:** Inject overlay into game's render pipeline
3. **Hotkey Support:** Use existing hotkey infrastructure for ESP toggles
4. **Menu Integration:** ESP settings accessible via ImGui-style menu

## Detection Evasion

The internal overlay approach minimizes detection risk:

1. **DirectX Rendering:** Uses same API as Apex Legends
2. **No External Windows:** Overlay rendered onto game screen
3. **Memory Pattern Hiding:** ESP data structures mixed with game entities
4. **Team Color Camouflage:** Team colors match Apex's native UI

## Future Enhancements

- [ ] Bullet trace rendering
- [ ] Projectile prediction lines
- [ ] Aim assist visualization
- [ ] Kill feed integration
- [ ] Radar overlay
- [ ] 3D world-to-screen projection optimization

## Troubleshooting

**Common Issues:**

1. **ESP not showing:**
   - Verify DirectX initialization succeeded
   - Check entity list offset pattern matches game version
   - Ensure ESP is enabled in configuration

2. **Boxes rendering incorrectly:**
   - Adjust `box_padding` and `corner_size` in config
   - Verify `line_thickness` matches desired visual weight

3. **Glow effects too strong/weak:**
   - Adjust `glow_intensity` (0.5-1.5 recommended)
   - Enable/disable `dynamic_glow` for distance-based intensity

## Credits

ESP Overlay System designed following Kernaim/Ignite/Chudvision patterns for Apex Legends kernel-level cheat.
