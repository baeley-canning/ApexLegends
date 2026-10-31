# Apex Cheat Launch Sequence

## Current Phase: Phase 4 - C++/ImGui Internal Overlay

### Launch Order Preference
1. **Start cheat first** (launcher.py)
2. **Then boot Apex** (r5apex_dx12.exe)

This allows the kernel driver and overlay to be ready before Apex starts scanning.

---

## Launch Commands

### 1. Launch Cheat (C++/ImGui Overlay)

```cmd
cd C:\Users\New User\OneDrive\Desktop\QwenKern
python launcher.py
```

**What launcher does:**
- Initializes C++/ImGui menu system from `phase3_menu_system\imgui_integration`
- Registers hotkeys (INSERT=toggle menu, HOME=toggle ESP)
- Starts C++ overlay process
- Optionally launches Apex if configured

### 2. Launch Apex Legends

```cmd
"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
```

---

## Hotkeys

| Key | Action |
|-----|--------|
| INSERT (0x90) | Toggle cheat menu visibility |
| HOME (0x24) | Toggle ESP overlay |

---

## Expected Windows

After launch, you should see:
- **Apex Legends Cheat Menu** - C++/ImGui window (600x500 at 100,100)
- **Apex Legends** - Game window (Respawn001 class)

---

## Verification

Run `verify_cheat_visibility.py` to confirm cheat is visible:

```cmd
python verify_cheat_visibility.py
```

Look for:
- Window class: `ApexCheatMenu`
- Window title: `Apex Legends Cheat Menu`
- Position/size: 600x500 at coordinates (100,100)

---

## Troubleshooting

### No cheat menu visible?
- Check hotkey registration: INSERT and HOME keys should toggle menu
- Verify C++ overlay compiled successfully
- Check DirectX 12 device creation in InitializeD3D12()

### Menu appears but crashes?
- DPG native library crashes (0xC0000005) are expected - subprocess isolation protects against them
- Consider increasing subprocess timeout in launcher.py

---

## Phase 4 Architecture

```
C:\Users\New User\OneDrive\Desktop\QwenKern\
├── phase3_menu_system\
│   └── imgui_integration\
│       ├── main.cpp              (Entry point with D3D12 overlay)
│       ├── menu_core.cpp         (ImGui-style tabbed menu)
│       ├── menu_core.hpp
│       ├── menu_config.hpp       (SharedMenuData structure)
│       ├── menu_renderer.hpp     (ESP rendering classes)
│       └── CMakeLists.txt
├── launcher.py                   (Launch orchestrator)
└── verify_cheat_visibility.py   (Verification script)
```

---

## Notes for Reset

- **User prefers C++/ImGui internal overlay** over external popup windows
- **Launch order matters**: cheat first, then Apex
- **Hotkeys are global**: registered via RegisterHotKey()
- **Shared memory IPC**: `Global\ApexCheatMenuData` for menu-driver communication
