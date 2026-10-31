# Phase 5 Quick Reference

**Project:** Apex Cheat Phase 5 - C++ ImGui with Hybrid Architecture  
**Location:** `C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase5_cpp_ImGui`  

---

## Build Commands

```bash
# Build DLL
cd "C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase5_cpp_ImGui"
msbuild apex_cheat.sln /p:Configuration=Release /p:Platform=x64

# Run with launcher
python launcher.py --both
```

---

## File Locations

| Component | Path |
|-----------|------|
| **Solution** | `phase5_cpp_ImGui\apex_cheat.sln` |
| **C++ DLL** | `phase5_cpp_ImGui\x64\Release\apex_cheat.dll` (after build) |
| **Python Wrapper** | `phase5_cpp_ImGui\python_wrapper\apex_cheat_py.py` |
| **Launcher** | `phase5_cpp_ImGui\launcher.py` |

---

## Hotkeys

| Key | Action | Description |
|-----|--------|-------------|
| **INSERT** (0x90) | Toggle Menu | Show/hide ImGui menu |
| **HOME** (0x24) | Toggle ESP | Show/hide ESP overlay |

---

## Detection Risk: LOW

- **D3D11 rendering** - Internal overlay, no separate process detection
- **Custom window class** - `ApexCheatMenu` with layered attributes
- **Hotkey API** - Standard Windows hotkey registration
- **Frame timing** - Configurable, human-like patterns

---

## Key C++ Functions

```cpp
// Initialization
bool CheatInitialize(HMODULE hModule, CheatConfig* config);
void CheatShutdown(void);

// Menu operations
void CheatShowMenu();
void CheatHideMenu();
void CheatToggleMenu();
bool CheatIsMenuVisible();

// ESP operations
void CheatShowESP();
void CheatHideESP();
void CheatToggleESP();
bool CheatIsESPEnabled();

// Player management
void CheatAddPlayer(PlayerInfo* player);
void CheatRemovePlayer(const char* name);
size_t CheatGetPlayerCount();
PlayerInfo* CheatGetPlayer(size_t index);

// Rendering
void CheatRenderFrame(ID3D11DeviceContext* ctx);
```

---

## Python Usage

```python
from apex_cheat_py import ApexCheat, PlayerInfo

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

# Toggle via hotkeys
cheat.toggle_menu()   # INSERT
cheat.toggle_esp()    # HOME
```

---

## Launch Order (Per User Preference)

1. **Cheat first** - C++ DLL loads, registers hotkeys
2. **Apex second** - Game starts with menu rendered on top

---

## Comparison: Phase 4 vs Phase 5

| Aspect | Phase 4 (DPG) | Phase 5 (C++ D3D11) |
|--------|---------------|---------------------|
| **Overlay Type** | External window | Internal D3D hook |
| **Detection Risk** | Medium-High | Low-Medium |
| **Rendering** | Dear PyGui | Native D3D11 |
| **Performance** | Good | Excellent |
| **Customization** | High (Python) | Medium (C++ config) |

---

## Next Steps

1. **Build DLL** - `msbuild apex_cheat.sln /p:Configuration=Release`
2. **Test in VM** - Launch cheat first, then Apex
3. **Verify visibility** - INSERT for menu, HOME for ESP

---

*Quick Reference - Created October 14, 2026*
