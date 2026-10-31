# Phase 4 Cheat Launch Guide

## Quick Start

### Option 1: Full Launch (Recommended)
```bash
cd "C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase4_apex_cheat"
python launcher.py --both
```
This launches:
1. **External Tkinter Menu** first
2. **Apex Legends** second

### Option 2: Manual Launch

**Terminal 1 - Cheat Menu:**
```bash
python external_menu.py
```

**Terminal 2 - Apex:**
```bash
# From VM or production
C:\Users\New User\VM\Apex\r5apex_dx12.exe
```

## Key Bindings

| Key | Action | When to Use |
|-----|--------|-------------|
| **INSERT** | Toggle menu visibility | Press during gameplay to show/hide menu |
| **HOME** | Toggle ESP overlay | Show/hide player indicators |

## Menu Features

### What You'll See
- **Title:** "Apex Cheat Menu"
- **Position:** Independent window (not locked to Apex)
- **Always on Top:** Menu stays visible over game
- **Transparent Background:** Minimal visual impact

### Menu Sections
- **ESP Overlay** - Toggle on/off
- **Aimbot** - Enable/disable aim assistance
- **Humanizer** - Turn human-like patterns on/off

## Troubleshooting

### Menu not visible?
1. Press **INSERT** to toggle
2. Check menu is on top (always-on-top enabled)
3. Look for "Apex Cheat Menu" window

### Hotkeys not working?
- Run as administrator (for global hotkey registration)
- Check no other apps use INSERT/HOME keys

### Menu too close to game?
Edit `window_position` in `external_menu.py`:
```python
window_position: tuple[int, int] = (50, 50)  # Adjust X, Y
```

## Launch Sequence Verification

You should see this order:

```
[Time 0] python external_menu.py
         └─> Menu window appears

[Time +2s] python launcher.py --both (or launch Apex manually)
           └─> Apex starts with menu already visible

[Time +5s] Gameplay begins
           └─> INSERT to toggle menu during matches
```

## Next Steps After Launch

1. **Test INSERT key** - Press to toggle menu visibility
2. **Try HOME key** - Toggle ESP overlay
3. **Move menu** - Drag window to preferred position
4. **Start Apex match** - Menu stays visible during gameplay

---

*Phase 4 Launch Guide - Created October 13, 2026*
