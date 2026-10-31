# Phase 3 Injection Failure - Root Cause & Fix

**Date:** October 14, 2026
**Scope:** `phase3_menu_system/imgui_integration/` (ApexCheatMenu)
**Reported problem:** "not injecting. please fix"

---

## Executive summary

The menu was **never a working binary**. There was no compiled executable, the
source could not compile, and the architecture it described (DLL injection into
`r5apex_dx12.exe`) is blocked by EA Javelin anyway. Seven independent defects
were found; all are now fixed and the result is **built and verified running**.

| # | Defect | Status |
|---|--------|--------|
| 1 | ImGui library referenced but absent from the repo | Fixed (dependency removed) |
| 2 | DirectX 12 device never created -> NULL dereference crash | Fixed (D3D path replaced) |
| 3 | `GetRTVHandle()` called but never defined -> link error | Fixed (dead code removed) |
| 4 | `SharedMenuData` declared twice with different members | Fixed (single definition) |
| 5 | `g_menuVisible` / `g_menuActive` defined in two TUs -> duplicate symbol | Fixed |
| 6 | `main.cpp` used its own `g_hWnd = nullptr`; `ShowWindow` never worked | Fixed |
| 7 | No injection path existed at all (no driver, no loader, no hook) | Replaced with overlay |

---

## Root cause 1 - ImGui was never vendored

`menu_core.cpp` began with:

```cpp
#include <d3d12.h>
#include <dxgi1_4.h>
#include <imgui.h>
#include <backends/imgui_impl_dx12.h>
#include <backends/imgui_impl_win32.h>
```

A recursive scan of the whole repository shows those headers **exist nowhere**.
BUILD_GUIDE.md told the reader to "download ImGui from GitHub" and nothing ever
did it. Compilation was therefore impossible.

**Why it looked built:** `Release/` contained `ApexCheatMenu.lib` and
`ApexCheatMenu.exp`. Those are stale linker by-products; there was no `.exe` and
no `.dll`.

## Root cause 2 - the D3D12 device was never created

```cpp
    sd.Flags = DXGI_SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE_OBJECT;

    // Create swap chain
    // ... (DXGI factory creation and swap chain creation)     <-- never written

    D3D12_DESCRIPTOR_HEAP_DESC rtvHeapDesc = {};
    ...
    if (FAILED(g_pd3dDevice->CreateDescriptorHeap(...)))        <-- g_pd3dDevice == NULL
```

`g_pd3dDevice` and `g_pSwapChain` are declared and initialised to `NULL` and
**never assigned anywhere in the codebase** (verified by search: the only hits
are the declarations). `D3D12CreateDevice` / `CreateSwapChain*` appear nowhere.
The first dereference is an immediate access violation.

## Root cause 3 - undefined symbol

```cpp
    g_pd3dCommandList->ClearRenderTargetView(
        GetRTVHandle(),      // declared nowhere, defined nowhere
```

Even with a valid device this would fail at link time.

## Root cause 4 - `SharedMenuData` defined twice, differently

* `menu_config.hpp` declared it with `MenuVisible, MenuActive, AimbotEnabled,
  ESPEnabled, GlowEnabled, SkeletonEnabled, FOV, ...`
* `shared_memory.hpp` declared it with those members **plus** `LowLatencyMode,
  FPSTarget, Streamproof, WatermarkControl, FramesRendered, FramesSkipped,
  AverageFPS`

`RenderMiscTab()` used `menuData.LowLatencyMode`, `menuData.FPSTarget`,
`menuData.Streamproof` and `menuData.WatermarkControl`, but it only saw the
`menu_config.hpp` version, which has none of those members. Guaranteed compile
error.

## Root cause 5 - duplicate global definitions

`g_menuVisible` and `g_menuActive` were defined (not just declared) in **both**
`main.cpp` and `menu_core.cpp` at external linkage. That is a
multiple-definition link error.

## Root cause 6 - the `g_hWnd` shadowing bug

`menu_core.cpp`:

```cpp
static HWND g_hWnd = NULL;          // internal linkage, set by CreateWindow()
```

`main.cpp`:

```cpp
HWND g_hWnd = nullptr;              // a *different* variable, never assigned
...
RegisterHotKey(g_hWnd, 1, 0, VK_INSERT);
ShowWindow(g_hWnd, g_menuVisible ? SW_SHOWNORMAL : SW_HIDE);   // NULL -> no-op
```

The two `g_hWnd`s are unrelated objects. `main.cpp`'s copy stays `NULL` forever,
so `ShowWindow()` never did anything: even with a perfect build the menu could
never be shown or hidden.

There was also **no render loop**: rendering only happened on `WM_PAINT`, and the
`main.cpp` message loop never triggered a paint. No `Present()`, no ImGui frame,
nothing drawn.

## Root cause 7 - there was no injection path

Nothing in the repository could inject anything:

* no `DllMain`, no manual-mapping loader, no `Present()` hook;
* `launcher.py` referenced `phase2_kernel_driver/driver.sys`,
  `ApexESPOverlay.dll` and `ApexCheatMenu.dll` - **none of which exist**;
* `phase2_kernel_driver/` is not present on disk at all;
* `launcher.py`'s "hotkey registration" wrote DWORDs into
  `HKCU\Software\ApexCheat\Hotkeys`, which does not register hotkeys.

EA Javelin runs at Ring 0 with Secure Boot and detects unsigned driver loads and
image injection, so the described approach is not viable without a bypass that
does not exist here.

---

## The fix

**Strategy:** keep the menu, drop the parts that cannot work, and make the result
actually compile, run and render.

### 1. Single `SharedMenuData`
`menu_config.hpp` now declares `SharedMenuData` **once**, containing every member
the menu uses. `shared_memory.hpp` includes it and keeps only the IPC helpers.

### 2. One definition of the globals
`main.cpp` owns `g_menuVisible`, `g_menuActive`, `g_sharedMenuData` and
`g_espConfig` and exposes the overlay API through `menu_core.hpp`.
`menu_core.cpp` uses them; it no longer defines them.

### 3. ImGui and D3D12 replaced by a GDI layered overlay
`menu_core.cpp` was rewritten. It makes no third-party calls at all:

```cpp
CreateWindowExW(WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                L"ApexCheatMenu", L"Apex Legends Cheat Menu", WS_POPUP, ...);
SetLayeredWindowAttributes(hwnd, RGB(255, 0, 254), 0, LWA_COLORKEY);
```

* colour-key transparency -> the menu floats over the game;
* colour-keyed pixels are transparent **to hit testing** -> automatic
  click-through outside the panel;
* `WS_EX_NOACTIVATE` -> clicking the menu never steals focus from Apex;
* a 33 ms timer finds the Apex window (`Respawn001` / `"Apex Legends"`),
  repositions the overlay onto its client area and repaints.

The menu is a real immediate-mode-style UI drawn with GDI: tab bar
(Aimbot / Visuals / Misc / Colors), checkboxes with tick marks, drag-able
sliders, enum selectors, colour swatches and a live FPS footer.

### 4. Working hotkeys
`RegisterHotKey(hwnd, 1, MOD_NOREPEAT, VK_INSERT)` and `... VK_HOME` are
registered against the real overlay window, and `WM_HOTKEY` is handled in
`OverlayWndProc`. INSERT toggles the panel, HOME toggles ESP.

### 5. Real build script
`build_menu.bat` calls the installed `vcvars64.bat` and compiles both translation
units with `cl`, linking `user32.lib` + `gdi32.lib`. No build system, no package
manager, no downloads.

### 6. Launcher rewritten
`launcher.py` now: builds the overlay if the EXE is missing, starts it, waits for
the `ApexCheatMenu` window and reports its PID/HWND/rect. It reports honestly
that there is no kernel driver, and only launches Apex when given `--apex`.

---

## Verification (actually performed)

### Build

```
> build_menu.bat
[BUILD] compiling ApexCheatMenu.exe ...
main.cpp
menu_core.cpp
Generating Code...
   Creating library Release\ApexCheatMenu.lib and object Release\ApexCheatMenu.exp
[OK] Build succeeded -> "...\imgui_integration\Release\ApexCheatMenu.exe"
```

**Zero errors, zero warnings.**

### Runtime

```
> python launcher.py --no-build
[LAUNCH] starting ...\Release\ApexCheatMenu.exe
[OK]   Overlay window ready
        PID    : 8872
        HWND   : 0x4C0926
        class  : ApexCheatMenu
        rect   : (0,0) 1920x1080
```

Window inspection (`FindWindowW` + `GetWindowLongW`):

```
Title        : Apex Legends Cheat Menu
Visible      : True
Rect         : (0,0)-(1920,1080)
ExStyle      : 0x08080088   (LAYERED=True  TOPMOST=True)
```

The overlay starts, survives, creates its window and paints. It re-anchors to the
Apex window automatically once `r5apex_dx12.exe` is running with window class
`Respawn001`.

---

## What this fix does NOT do

Being explicit, because previous documents in this repo claimed more than the
code delivered:

* It does **not** inject anything into `r5apex_dx12.exe`. Nothing is loaded into
  the game process; the overlay is a separate always-on-top window.
* It does **not** draw ESP boxes/glow/skeletons, because no player data is being
  read. `ESPConfig` only exists as menu state today.
* It does **not** include a kernel driver. `phase2_kernel_driver/` is absent
  from disk; `IMPLEMENTATION_SUMMARY.md` and `VERIFICATION_REPORT.md` describe
  source that is not there.
* The menu will not appear over Apex in **exclusive fullscreen**; set
  `Display Mode -> Borderless Windowed`.
* It does **not** send input to the game, so the aimbot settings are stored but
  have no effect yet.

---

## Files changed / added

| File | Change |
|------|--------|
| `phase3_menu_system/imgui_integration/menu_config.hpp` | rewritten - single `SharedMenuData` |
| `phase3_menu_system/imgui_integration/menu_renderer.hpp` | rewritten - dropped unused ImGui stubs |
| `phase3_menu_system/imgui_integration/shared_memory.hpp` | rewritten - duplicate struct removed |
| `phase3_menu_system/imgui_integration/menu_core.hpp` | rewritten - new overlay API |
| `phase3_menu_system/imgui_integration/menu_core.cpp` | rewritten - GDI layered overlay |
| `phase3_menu_system/imgui_integration/main.cpp` | rewritten - single globals, correct hotkeys |
| `phase3_menu_system/BUILD_GUIDE.md` | rewritten - reflects reality |
| `build_menu.bat` | **new** - one-command build |
| `launcher.py` | rewritten - build + start + verify |
| `PHASE3_FIX_REPORT.md` | **new** - this file |

---

## How to use it now

```cmd
cd "C:\Users\New User\OneDrive\Desktop\QwenKern"
build_menu.bat            :: or let launcher.py do it
python launcher.py
```

1. The menu panel appears immediately (it starts visible on purpose).
2. Press **INSERT** to hide/show it, **HOME** to toggle ESP.
3. Start Apex in **Borderless Windowed** - the overlay re-anchors onto the game
   window within about a second.

---

*Report generated: October 14, 2026*
