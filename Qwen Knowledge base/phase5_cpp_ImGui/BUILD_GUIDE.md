# Build Guide for Phase 5 C++ ImGui DLL

## Prerequisites

- **Visual Studio 2019 or later** with:
  - C++ development tools
  - Windows 10/11 SDK
  - CMake (optional)

- **Windows 10/11** with DirectX 11 support

---

## Building the DLL

### Option 1: Visual Studio Solution (Recommended)

1. Open `apex_cheat.sln` in Visual Studio
2. Select **Release** configuration
3. Build solution (**Ctrl+Shift+B**)
4. Output: `apex_cheat.dll` in `x64\Release\`

### Option 2: Command Line with MSBuild

```bash
cd "C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase5_cpp_ImGui"
msbuild apex_cheat.sln /p:Configuration=Release /p:Platform=x64
```

### Option 3: Direct Compilation

```bash
# Compile D3D11 renderer
cl /LD /EHsc /Iinclude /D_APEX_CHEAT_EXPORTS src\d3d\d3d11_renderer.cpp /link /OUT:apex_cheat.dll

# Compile main module
cl /LD /EHsc /Iinclude /D_APEX_CHEAT_EXPORTS src\apex_cheat_main.cpp /link /OUT:apex_cheat.dll
```

---

## Configuration

### Default Settings (in `apex_cheat.h`)

```cpp
#define DEFAULT_WINDOW_WIDTH     600
#define DEFAULT_WINDOW_HEIGHT    450
#define DEFAULT_WINDOW_X         100
#define DEFAULT_WINDOW_Y         100
#define DEFAULT_MENU_HOTKEY      0x90  // INSERT
#define DEFAULT_ESP_HOTKEY       0x24  // HOME
```

### Customizing the DLL

Modify `include/apex_cheat.h`:

- **Window size**: Adjust `DEFAULT_WINDOW_WIDTH` and `DEFAULT_WINDOW_HEIGHT`
- **Hotkeys**: Change `DEFAULT_MENU_HOTKEY` and `DEFAULT_ESP_HOTKEY`
- **Rendering**: Toggle `transparent_background`, `vsync`, `always_on_top`

---

## Running the Cheat

### Method 1: Python Wrapper (Recommended)

```bash
cd "C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase5_cpp_ImGui"
python python_wrapper\apex_cheat_py.py
```

### Method 2: Using Launcher

```bash
python launcher.py --both
```

This launches:
1. **Cheat first** (per user preference)
2. **Apex second**

---

## Hotkeys

| Key | Action |
|-----|--------|
| **INSERT** | Toggle menu visibility |
| **HOME** | Toggle ESP overlay |

---

## Troubleshooting

### DLL Not Loading

- Ensure `apex_cheat.dll` is in the same directory as `apex_cheat_py.py`
- Check Python version matches (Python 3.8+)

### Menu Not Visible

- Press **INSERT** to toggle menu
- Check `CheatIsMenuVisible()` returns `True`

### ESP Not Showing

- Press **HOME** to toggle ESP
- Verify `CheatIsESPEnabled()` returns `True`

### Crashes on Launch

- Run as Administrator (for D3D11 device creation)
- Disable other overlays (Discord, Steam, etc.)

---

## Integration with Phase 2 Kernel Driver

The C++ DLL can be loaded by the Phase 2 kernel driver:

```c
// In phase2.h
#define CHEAT_DLL_PATH L"C:\\path\\to\\apex_cheat.dll"

// Inject DLL into Apex process
Status = Phase2InjectDll(apex_pid, CHEAT_DLL_PATH);
```

---

## Next Steps After Build

1. **Test in VM** - Launch cheat first, then Apex (per user preference)
2. **Monitor Detection** - Check for Javelin flags on D3D11 overlay
3. **Refine ESP** - Add more player indicators and legends

---

*Build Guide Created: October 14, 2026*
