# Apex Cheat Phase 5 - C++ ImGui with Hybrid Architecture

**Status:** In Progress  
**Target:** Internal ImGui overlay (Kernaim/Ignite/Chudvision pattern) with D3D11 rendering  
**Architecture:** Hybrid Python + C++ DLL  

---

## Overview

Phase 5 implements a **native C++ ImGui overlay system** inspired by Kernaim, Ignite, and Chudvision cheats, designed to evade Javelin detection while providing a responsive, user-friendly interface.

### Why Native C++ ImGui?

- **True Internal Overlay** - Renders directly onto Apex's DirectX pipeline
- **Lower Detection Risk** - No separate process detection like Dear PyGui external windows
- **Frame-Perfect Rendering** - D3D11 hook renders on every present call
- **Kernaim/Ignite/Chudvision Pattern** - Matches proven cheat menu implementations

---

## Architecture

### Hybrid Approach (Chudvision Pattern)

```
┌─────────────────────────────────────────────┐
│           Apex Legends Game                 │
│  ┌───────────────────────────────────────┐  │
│  │   D3D11 Present Hook                  │  │
│  │   ├─ Menu Rendering (ImGui-style)     │  │
│  │   └─ ESP Rendering (boxes, health)    │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────┐
│      Python Wrapper (apex_cheat_py.py)     │
│  ├─ Configuration interface                │
│  ├─ Hotkey registration                    │
│  └─ Player management                      │
└─────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────┐
│      C++ DLL (apex_cheat.dll)              │
│  ├─ D3D11 Renderer                         │
│  ├─ Menu Window                            │
│  └─ ESP Overlay                            │
└─────────────────────────────────────────────┘
```

---

## Project Structure

```
phase5_cpp_ImGui/
├── include/
│   ├── apex_cheat.h          # Main header with C API exports
│   └── d3d11_renderer.h      # D3D11 rendering backend
├── src/
│   ├── d3d/
│   │   └── d3d11_renderer.cpp    # D3D11 implementation
│   └── apex_cheat_main.cpp       # Main DLL entry point
├── python_wrapper/
│   └── apex_cheat_py.py        # Python wrapper for C++ DLL
├── launcher.py                 # Launch cheat + Apex
└── README.md                   # This file
```

---

## Key Features

### Menu System (ImGui-style)
- **Clean dark theme** (#1a1a2e background)
- **Tabs and sections** for ESP, Aim, Humanizer, Radar
- **Draggable window** with transparency
- **INSERT key toggle** for visibility

### ESP Overlay
- **Player boxes** with team colors
- **Health/shield bars**
- **Player names and legends**
- **Distance indicators**

### D3D11 Rendering
- **Internal overlay** via DirectX hook
- **Frame-accurate** rendering on present call
- **Transparent background** support
- **VSync synchronization**

---

## Quick Start

### Building the C++ DLL

```bash
# Prerequisites: Visual Studio 2019+ with Windows SDK
cd phase5_cpp_ImGui

# Build in Release mode
msbuild apex_cheat.sln /p:Configuration=Release
```

### Using Python Wrapper

```python
from apex_cheat_py import ApexCheat, PlayerInfo

# Initialize cheat
cheat = ApexCheat("apex_cheat.dll")
cheat.start()

# Add players for ESP
player = PlayerInfo(
    name="Enemy1",
    x=100.0, y=200.0,
    health=100,
    legend="Lifeline",
    weapon="R-99"
)
cheat.dll_wrapper.add_player(player)

# Toggle menu/ESP via hotkeys
cheat.toggle_menu()   # INSERT
cheat.toggle_esp()    # HOME
```

---

## Hotkeys

| Key | Action | Description |
|-----|--------|-------------|
| **INSERT** | Toggle Menu | Show/hide ImGui menu |
| **HOME** | Toggle ESP | Show/hide ESP overlay |

---

## Detection Risk Assessment

Based on Javelin research for internal D3D11 overlay approach:

| Feature | Detection Risk | Ban Likelihood |
|---------|----------------|----------------|
| D3D11 rendering | Low | ★☆☆ |
| Internal overlay (on-game) | Low-Medium | ★☆☆ |
| Window class randomization | Low | ★☆☆ |
| Hotkey registration | Low | ★☆☆ |
| Frame-accurate timing | Low | ★☆☆ |

**Total Risk: LOW** - Native C++ D3D11 approach matches Kernaim/Ignite/Chudvision detection evasion.

---

## Next Steps

1. **Build C++ DLL** - Compile with Visual Studio
2. **Test in VM** - Launch cheat first, then Apex (per user preference)
3. **Monitor Detection** - Check for Javelin flags on D3D11 overlay
4. **Refine ESP** - Add more player indicators and legends

---

## Comparison: Phase 4 (Python) vs Phase 5 (C++)

| Aspect | Phase 4 (DPG) | Phase 5 (C++ D3D11) |
|--------|---------------|---------------------|
| **Overlay Type** | External (separate window) | Internal (D3D hook) |
| **Detection Risk** | Medium-High | Low-Medium |
| **Rendering** | Dear PyGui | Native D3D11 |
| **Performance** | Good | Excellent |
| **Customization** | High (Python) | Medium (C++ config) |
| **Complexity** | Medium | Medium-High |

---

*Phase 5 Implementation - Created October 14, 2026*
