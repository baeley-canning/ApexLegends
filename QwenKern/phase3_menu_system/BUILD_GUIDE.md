# Phase 3 Menu System - Build Guide

## Overview

The Phase 3 menu is a **self-contained overlay**: a transparent, always-on-top,
click-through window that draws the menu directly over the Apex window.

It has **no third-party dependencies**. It links only against `user32.lib` and
`gdi32.lib`, so it builds with nothing but the MSVC toolchain + Windows SDK
already installed on this machine.

> **Why not DirectX 12 + Dear ImGui?**
> The original design called for a D3D12 + ImGui overlay. That code could never
> build (the ImGui library was never vendored into the repo) and would have
> crashed on the first frame because the D3D12 device was never created. It also
> implied DLL injection into `r5apex_dx12.exe`, which is blocked by EA Javelin
> (kernel anti-cheat + Secure Boot). The current implementation avoids the whole
> problem: it renders over the game without ever opening the game process.

---

## 1. Build

### One command

```cmd
cd "C:\Users\New User\OneDrive\Desktop\QwenKern"
build_menu.bat
```

That is all. It calls `vcvars64.bat`, then compiles `main.cpp` + `menu_core.cpp`
into:

```
phase3_menu_system\imgui_integration\Release\ApexCheatMenu.exe
```

### Expected output

```
[BUILD] compiling ApexCheatMenu.exe ...
main.cpp
menu_core.cpp
Generating Code...
   Creating library Release\ApexCheatMenu.lib and object Release\ApexCheatMenu.exp
[OK] Build succeeded -> "...\Release\ApexCheatMenu.exe"
```

This build is **verified clean**: no errors, no warnings.

### Toolchain actually used

| Component | Path |
|-----------|------|
| MSVC      | `C:\BuildTools\VC\Tools\MSVC\14.44.35207` |
| vcvars64  | `C:\BuildTools\VC\Auxiliary\Build\vcvars64.bat` |
| Windows SDK | `C:\Program Files (x86)\Windows Kits\10` (10.0.26100.0) |

If `build_menu.bat` fails with *"vcvars64.bat not found"*, edit the `VCVARS`
variable at the top of `build_menu.bat`.

---

## 2. Run

```cmd
python launcher.py              :: build (if needed) + start the overlay
python launcher.py --no-build   :: start an already-built overlay
python launcher.py --apex       :: also launch Apex Legends afterwards
```

Or start the executable directly:

```cmd
phase3_menu_system\imgui_integration\Release\ApexCheatMenu.exe
```

### Hotkeys

| Key | Action |
|-----|--------|
| **INSERT** | Show / hide the menu panel |
| **HOME** | Toggle ESP |

### Stopping it

```cmd
taskkill /IM ApexCheatMenu.exe /F
```

---

## 3. Source Layout

```
phase3_menu_system/
├── BUILD_GUIDE.md            <- this file
├── imgui_integration/
│   ├── main.cpp              <- WinMain + DLL-style exports
│   ├── menu_core.cpp         <- overlay window, painting, input, hotkeys
│   ├── menu_core.hpp         <- public API of the overlay module
│   ├── menu_config.hpp       <- SharedMenuData (single definition)
│   ├── menu_renderer.hpp     <- PlayerEntity + ESPConfig
│   ├── shared_memory.hpp     <- Global\ApexCheatMenuData helpers
│   └── Release/
│       └── ApexCheatMenu.exe <- build output
├── python_wrapper/
│   └── menu_interface.py
└── tests/
    ├── test_menu.cpp
    └── test_esp.cpp
```

### The `imgui_integration` folder name

The directory is still called `imgui_integration` for continuity with the
original layout, but it no longer contains any ImGui code.

---

## 4. How the overlay works

```
+----------------------------------------------------------+
|  ApexCheatMenu.exe                                       |
|                                                          |
|   CreateWindowEx(WS_EX_LAYERED | WS_EX_TOPMOST |         |
|                  WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,    |
|                  WS_POPUP)                               |
|                                                          |
|   SetLayeredWindowAttributes(KEY_COLOR = RGB(255,0,254)) |
|        -> every key-coloured pixel is transparent AND     |
|           transparent to mouse input (click-through)      |
|                                                          |
|   Timer every 33 ms:                                     |
|     * find the "Respawn001" / "Apex Legends" window      |
|     * resize/move the overlay onto it                    |
|     * repaint menu with GDI                              |
+----------------------------------------------------------+
```

Key points:

* **Nothing is injected.** The Apex process is never opened or modified. The
  overlay simply floats above it, exactly like Discord's in-game overlay.
* **Click-through.** Colour-keyed pixels pass mouse input to the game; only the
  menu panel itself is clickable.
* **Global hotkeys.** `RegisterHotKey` against the overlay window, so
  INSERT / HOME work regardless of which app has focus.
* **Interactive.** Tabs, checkboxes, sliders, enum selectors and colour swatches
  are all live - click and drag.

### Requirement: Apex must be in Borderless / Windowed mode

Windows cannot composite a topmost window over an **exclusive fullscreen** swap
chain. In Apex set:

```
Settings -> Video -> Display Mode -> Borderless Windowed
```

If the menu does not appear over the game, this is almost always the reason.

---

## 5. Shared memory

`shared_memory.hpp` publishes the same `SharedMenuData` layout (declared once,
in `menu_config.hpp`) into a named section so a kernel driver or an external
tool can read the user's configuration:

| Object | Name |
|--------|------|
| Section | `Global\ApexCheatMenuData` |
| Menu event | `Global\ApexCheatMenuEvent` |
| ESP event | `Global\ApexCheatESPEvent` |

The helper functions (`CreateSharedMemory`, `MapSharedMemory`,
`CreateMenuEvent`, ...) are `inline` in the header, so nothing extra needs to be
linked.

---

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ApexCheatMenu.exe` missing | Not built | Run `build_menu.bat` |
| `vcvars64.bat not found` | Build tools moved | Fix `VCVARS` inside `build_menu.bat` |
| Menu invisible over the game | Apex in exclusive fullscreen | Switch to Borderless Windowed |
| Nothing appears at all | INSERT toggled the menu off | Press INSERT again |
| Menu reappears unexpectedly | Window resized / game minimised | The 33 ms timer re-anchors it; wait ~1 s |
| Hotkeys do nothing | Another app claimed INSERT/HOME | Close that app, or edit the `RegisterHotKey` calls in `menu_core.cpp` |
| Overlay won't start twice | Already running | `taskkill /IM ApexCheatMenu.exe /F` |

### Verifying it is working

```cmd
python verify_cheat_visibility.py
```

Look for a window with class **`ApexCheatMenu`** and title
**`Apex Legends Cheat Menu`**, style `WS_EX_LAYERED | WS_EX_TOPMOST`.

---

## 7. Not implemented (deliberately)

* **Kernel driver.** `phase2_kernel_driver/` does not exist on disk;
  `IMPLEMENTATION_SUMMARY.md` / `VERIFICATION_REPORT.md` describe a driver whose
  source is absent. There is therefore no `driver.sys` and no kernel component.
* **DLL injection / manual mapping.** There is no assembly or manual-mapping
  loader and no `Present()` hook. Injecting into `r5apex_dx12.exe` is blocked by
  EA Javelin, so this route is intentionally not used.
* **ESP rendering.** The ESP *settings* live in the menu (`ESPConfig`), but no
  entity extraction or world-to-screen maths is wired up - that requires
  readable player data, which in turn requires either a driver or a bypassed
  game process.

Everything the overlay can own - the menu, the window, the hotkeys and the
configuration model - is real, built and running.

---

*Build Guide updated: October 14, 2026*
