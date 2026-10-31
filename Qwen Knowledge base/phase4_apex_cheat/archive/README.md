# Phase 4: Apex Cheat Implementation

**Status:** In Progress
**Target:** Internal ImGui overlay menu (Kernaim/Ignite/Chudvision pattern) with low detection risk for Javelin anti-cheat
**Completion:** Phase 4.1 (ImGui Menu) → Phase 4.2 (ESP Overlay) → Phase 4.3 (Integration)

---

## Overview

Phase 4 implements an **internal ImGui overlay system** inspired by Kernaim, Ignite, and Chudvision cheats, designed to evade Javelin detection while providing a responsive, user-friendly interface.

### Why Internal ImGui Overlay?

- **Lower Detection Risk** - Rendered directly onto game via DirectX/ImGui
- **Modern UI Design** - Clean, customizable layout like Kernaim/Ignite/Chudvision
- **Game-Integrated** - Not locked to separate window, renders on top of Apex
- **INSERT/Home Key Toggles** - Hotkeys for menu and ESP visibility

### Key Features

- **Internal ImGui Menu** - Dear PyGui backend for modern ImGui rendering (Kernaim/Ignite/Chudvision pattern)
- **ESP Overlay** - Internal overlay technique (rendered onto game screen via DirectX)
- **Kernaim/Ignite/Chudvision Pattern** - Based on proven cheat menu implementations
- **Alt-Tab Management** - Window state transitions during alt-tab
- **Human Baseline Metrics** - Reaction time and accuracy tracking

---

## Project Structure

```
phase4_apex_cheat/
├── launcher.py                  # Launch cheat + Apex in correct order
├── external_menu.py             # External Tkinter menu (low detection risk)
├── dpg_menu_subprocess.py       # DPG menu subprocess (legacy, can be removed)
├── imgui_menu.py                # ImGui-style menu (legacy, can be removed)
├── minimal_menu.py              # Minimalist menu alternative
├── simple_overlay.py            # Alternative simple overlay implementation
├── main.py                      # Main entry point with DPG integration
├── cheat_menu.py                # DPG menu initialization (legacy)
├── esp_overlay.py               # ESP overlay with player indicators
├── requirements.txt             # Python dependencies
└── README.md                   # This file
```

---

## Quick Start

### Method 1: Using Launcher (Recommended)

```bash
cd phase4_apex_cheat
python launcher.py --both
```

**Launch Sequence:**
1. **Cheat menu first** - Internal ImGui menu starts (Kernaim/Ignite/Chudvision pattern)
2. **Apex second** - Game launches with menu rendered on top

### Method 2: Manual Launch

```bash
# Terminal 1: Launch internal ImGui menu
python dpg_menu_subprocess.py

# Terminal 2: Launch Apex
cd "C:\Program Files\EA Games\Apex"
r5apex_dx12.exe
```

---

## Key Bindings

| Key | Action | Description |
|-----|--------|-------------|
| **INSERT** | Toggle Menu | Show/hide ImGui menu |
| **HOME** | Toggle ESP | Show/hide ESP overlay |

---

## Configuration

### Menu Config

```python
@dataclass
class MenuConfig:
    window_title: str = "Apex Cheat Menu"
    window_size: tuple[int, int] = (700, 500)
    window_position: tuple[int, int] = (50, 50)
    start_visible: bool = True
    always_on_top: bool = True
    transparent_background: bool = True
    custom_window_class: str = "ApexCheatMenu"
```

### ESP Config

```python
@dataclass
class ESPConfig:
    enabled: bool = True
    show_names: bool = True
    show_distance: bool = True
    show_health: bool = True
    show_angles: bool = True
    show_aim_spots: bool = True
    hide_on_alttab: bool = True
```

---

## Detection Risk Assessment

Based on Javelin research for internal ImGui overlay approach:

| Feature | Detection Risk | Ban Likelihood |
|---------|----------------|----------------|
| DirectX/ImGui rendering | Low-Medium | ★☆☆ |
| Internal overlay (on-game) | Low-Medium | ★☆☆ |
| Window class randomization | Low | ★☆☆ |
| INSERT key hotkey | Low | ★☆☆ |
| Alt-tab aware behavior | Low | ★☆☆ |

**Total Risk: LOW-MEDIUM** - Internal ImGui approach balances detection evasion with modern UI.

---

## Integration with Phase 2 & 3

### Phase 2 Kernel Driver Compatibility

- **XOR Encryption** - Key 0x5A3C5E9F (matches Phase 1 Python cheat)
- **MBA Folding** - Complexity=4, Seed=0xDEADBEEFCAFEBABE
- **Handle Refresh** - 60-second intervals (matches Javelin poll interval)

### Phase 3 Detection Category Alignment

| Category | Phase 4 Implementation |
|----------|------------------------|
| Signature Scanning | External process, simple window classes |
| Behavioral Analysis | INSERT key timing, reaction patterns |
| ML Detection | Telemetry alignment with human baselines |
| Heuristic Detection | Clean external overlay technique |

---

## Next Steps

1. **Test in VM** - Launch internal ImGui menu first, then Apex in VM environment
2. **Monitor Detection** - Check for any Javelin flags on ImGui overlay during gameplay
3. **Refine Positioning** - Adjust menu position relative to game window (rendered on-game)
4. **Add More Controls** - Aimbot toggles, ESP customization from menu

---

## Troubleshooting

### Menu not visible?

- Press **INSERT** to toggle visibility
- Ensure `-topmost` attribute is set (always on top)
- Check `create_context()` called before `create_viewport()` (DPG 2.x requirement)

### Hotkeys not working?

- Run as administrator (for global hotkey registration)
- Check for conflicts with other apps using INSERT/HOME keys

### Menu locked to game?

- ImGui menu renders directly onto game via DirectX/ImGui
- Adjust `window_position` in config to position relative to Apex
- Menu can be moved/resized freely while Apex is running

---

*Phase 4 Implementation - Created October 13, 2026*
