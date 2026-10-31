# Phase 3 Menu System - Apex Legends Kernel-Level Cheat

## Overview

The Phase 3 menu system implements a C++/ImGui core with Python wrapper for configuration management, matching Kernaim/Ignite/Chudvision visual patterns. The system features DirectX overlay rendering and shared memory communication with the kernel driver.

## Architecture

### C++/ImGui Core (`imgui_integration/`)
- **menu_config.hpp** - Configuration constants, color palette, legend overrides
- **menu_renderer.hpp** - ESP rendering classes (PlayerEntity, ESPConfig)
- **menu_core.cpp/h** - Main menu with ImGui tabbed interface (Aimbot, Visuals, Misc, Colors)
- **shared_memory.hpp** - Kernel driver communication structures
- **main.cpp** - Entry point with hotkey registration (INSERT/Home)

### Python Wrapper (`python_wrapper/`)
- **menu_interface.py** - Python wrapper for C++ menu system
- **config_templates/menu_config.json** - Default configuration

## Features

### Visual Style (Kernaim/Ignite/Chudvision)
- Flat grey sliders
- Dark panels with transparency
- Tab bars: Aimbot, Visuals, Misc, Colors
- Legend-specific overrides (Wraith tight, Gibraltar loose)

### Hotkeys
- **INSERT** - Toggle menu visibility
- **HOME** - Toggle ESP overlay

### Shared Memory Communication
- Memory name: `Global\ApexCheatMenuData`
- Event names: `Global\ApexCheatMenuEvent`, `Global\ApexCheatESPEvent`

## Building

See `BUILD_GUIDE.md` for detailed compilation instructions.

### Quick Start

1. Configure Visual Studio project with ImGui backend
2. Add source files from `imgui_integration/`
3. Link DirectX 12 libraries
4. Build Release configuration

## Testing

Run test suites:

```bash
# Menu system tests
test_menu.exe

# ESP rendering tests  
test_esp.exe
```

## Usage

### Python Interface

```python
from python_wrapper.menu_interface import MenuInterface

menu = MenuInterface()
menu.start()

# Toggle menu
menu.toggle_menu()

# Update settings
menu._shared_data.FOV = 25.0
menu.update_menu_data(menu._shared_data)

# Save configuration
menu.save_config("menu_config.json")
```

## Directory Structure

```
phase3_menu_system/
├── imgui_integration/
│   ├── menu_config.hpp
│   ├── menu_renderer.hpp
│   ├── menu_core.cpp/h
│   ├── shared_memory.hpp
│   └── main.cpp
├── python_wrapper/
│   ├── menu_interface.py
│   └── config_templates/
│       └── menu_config.json
├── tests/
│   ├── test_menu.cpp
│   └── test_esp.cpp
└── BUILD_GUIDE.md
```

## Integration

1. Launch cheat first (`python launcher.py`)
2. Press INSERT to verify menu appears
3. Launch Apex Legends (`r5apex_dx12.exe`)

## Next Steps

- Implement ESP overlay rendering
- Add aimbot target acquisition
- Integrate kernel driver communication

---

*Phase 3 Menu System - October 14, 2026*