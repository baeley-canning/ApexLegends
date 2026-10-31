#!/usr/bin/env python3
"""
QwenKern launcher - Phase 3 overlay menu (+ optional Apex launch).

Launch order (documented user preference):
    1. start this launcher   -> builds and starts ApexCheatMenu.exe
    2. press INSERT          -> verify the overlay menu is on screen
    3. start Apex Legends    -> the overlay attaches to the game window

How it works
------------
ApexCheatMenu.exe owns a transparent, always-on-top, click-through layered
window.  It draws the menu directly over whatever is underneath it and tracks
the Apex window position.  It never opens the Apex process, so there is no
DLL to inject and nothing for the anti-cheat to find inside r5apex_dx12.exe.

Usage
-----
    python launcher.py              build (if needed) and start the overlay
    python launcher.py --no-build   start an already-built overlay
    python launcher.py --apex       also launch Apex Legends afterwards
"""

import argparse
import ctypes
import ctypes.wintypes as wt
import os
import subprocess
import sys
import time

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ROOT = os.path.dirname(os.path.abspath(__file__))

MENU_EXE = os.path.join(
    ROOT, "phase3_menu_system", "imgui_integration", "Release", "ApexCheatMenu.exe"
)
BUILD_SCRIPT = os.path.join(ROOT, "build_menu.bat")

APEX_CANDIDATES = [
    r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe",
    r"C:\Program Files (x86)\EA Games\Apex\r5apex_dx12.exe",
    r"C:\Program Files\EA Games\Apex\Apex\r5apex_dx12.exe",
]

OVERLAY_WINDOW_CLASS = "ApexCheatMenu"

user32 = ctypes.windll.user32

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def banner(text):
    print("\n" + "=" * 72)
    print("   " + text)
    print("=" * 72)


def find_window(window_class):
    """Return the HWND of a top-level window with the given class name."""
    hwnd = user32.FindWindowW(window_class, None)
    return hwnd if hwnd else 0


def window_rect(hwnd):
    r = wt.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(r))
    return r.left, r.top, r.right - r.left, r.bottom - r.top


# ---------------------------------------------------------------------------
# Step 1 - build
# ---------------------------------------------------------------------------
def build_overlay():
    if os.path.exists(MENU_EXE):
        print("[OK]   ApexCheatMenu.exe already built")
        return True

    print("[BUILD] ApexCheatMenu.exe is missing - running build_menu.bat ...")

    if not os.path.exists(BUILD_SCRIPT):
        print("[ERROR] build_menu.bat not found at %s" % BUILD_SCRIPT)
        return False

    result = subprocess.run(
        ["cmd", "/c", BUILD_SCRIPT],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )

    for line in (result.stdout or "").splitlines():
        print("        " + line)

    if result.returncode != 0 or not os.path.exists(MENU_EXE):
        print("[ERROR] build failed (exit code %s)" % result.returncode)
        return False

    print("[OK]   Build succeeded")
    return True


# ---------------------------------------------------------------------------
# Step 2 - start the overlay
# ---------------------------------------------------------------------------
def launch_overlay():
    if find_window(OVERLAY_WINDOW_CLASS):
        print("[OK]   Overlay already running (ApexCheatMenu window found)")
        return None

    print("[LAUNCH] starting %s" % MENU_EXE)

    proc = subprocess.Popen([MENU_EXE])

    # Give the window a moment to appear
    hwnd = 0
    for _ in range(50):
        time.sleep(0.1)
        hwnd = find_window(OVERLAY_WINDOW_CLASS)
        if hwnd:
            break

    if not hwnd:
        print("[ERROR] overlay process started (PID %d) but no window appeared"
              % proc.pid)
        return proc

    x, y, w, h = window_rect(hwnd)
    print("[OK]   Overlay window ready")
    print("        PID    : %d" % proc.pid)
    print("        HWND   : 0x%X" % hwnd)
    print("        class  : %s" % OVERLAY_WINDOW_CLASS)
    print("        rect   : (%d,%d) %dx%d" % (x, y, w, h))
    print("[INFO] Press INSERT to toggle the menu, HOME to toggle ESP.")
    return proc


# ---------------------------------------------------------------------------
# Step 3 - Apex
# ---------------------------------------------------------------------------
def find_apex():
    for path in APEX_CANDIDATES:
        if os.path.exists(path):
            return path
    return None


def launch_apex():
    path = find_apex()

    if not path:
        print("[WARN] r5apex_dx12.exe not found in any known location:")
        for c in APEX_CANDIDATES:
            print("        " + c)
        print("[INFO] Start Apex yourself - the overlay will attach automatically.")
        return

    print("[LAUNCH] starting Apex: %s" % path)
    try:
        proc = subprocess.Popen([path])
        print("[OK]   Apex running (PID %d)" % proc.pid)
        print("[INFO] The overlay re-anchors to the game window within ~1 second.")
    except OSError as exc:
        print("[ERROR] could not start Apex: %s" % exc)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="QwenKern overlay launcher")
    parser.add_argument("--no-build", action="store_true",
                        help="do not build, use the existing ApexCheatMenu.exe")
    parser.add_argument("--apex", action="store_true",
                        help="also launch Apex Legends after the overlay")
    args = parser.parse_args()

    banner("QWENKERN - PHASE 3 OVERLAY MENU")

    if not args.no_build:
        if not build_overlay():
            return 1

    proc = launch_overlay()
    if proc is None:
        # Already running elsewhere
        pass

    if args.apex:
        launch_apex()

    print("\n" + "-" * 72)
    print("Overlay is active.  Hotkeys:  INSERT = menu    HOME = ESP")
    print("Close it with:  taskkill /IM ApexCheatMenu.exe /F")
    print("-" * 72)

    return 0


if __name__ == "__main__":
    sys.exit(main())
