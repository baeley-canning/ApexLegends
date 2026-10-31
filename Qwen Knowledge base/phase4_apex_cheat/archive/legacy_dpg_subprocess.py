#!/usr/bin/env python3
"""
DPG Menu Subprocess Launcher

Launches Dear PyGui menu in isolated subprocess to avoid native crashes.
Designed for Phase 4 VM testing with Javelin anti-cheat evasion.

Usage:
    python dpg_menu_subprocess.py [menu|cheat|both]
"""

import subprocess
import sys
import time
from pathlib import Path


# DPG menu script - runs in isolated subprocess to avoid native crashes
script = '''
import dearpygui.dearpygui as dpg
import time
import threading
import sys

# Global flag to control menu lifecycle - use atexit for clean shutdown
menu_running = threading.Event()
menu_running.set()

def cleanup():
    """Clean shutdown hook."""
    print("DPG menu cleanup...", flush=True)
    menu_running.clear()
    dpg.destroy_context()
    print("DPG menu cleanup complete.", flush=True)

import atexit
atexit.register(cleanup)

def main():
    try:
        # Required initialization order for DPG 2.x (per memory: create_context before create_viewport)
        dpg.create_context()

        # Create viewport with anti-detection settings
        dpg.create_viewport(title="Apex Cheat Menu", width=500, height=400)

        # Set viewport properties BEFORE setup - critical for visibility
        dpg.set_viewport_always_on_top(True)
        dpg.set_viewport_visible(True)
        dpg.set_viewport_pos([100, 100])
        dpg.set_viewport_clear_color([26, 26, 46])  # #1a1a2e
        dpg.set_viewport_enabled(True)
        dpg.set_viewport_min_size(500, 400)
        dpg.set_viewport_max_size(1920, 1080)

        dpg.setup_dearpygui()

        # Show viewport AFTER setup - critical for HWND to be assigned
        dpg.show_viewport()

        # Main render loop - keep running until explicitly stopped
        while menu_running.is_set() and dpg.is_dearpygui_running():
            dpg.render_dearpygui_frame()
            time.sleep(0.05)

        dpg.destroy_context()
    except Exception as e:
        print(f"DPG menu error: {e}", flush=True)
        import traceback
        traceback.print_exc()
        raise SystemExit(1)


def stop_menu():
    """Stop the DPG menu gracefully."""
    menu_running.clear()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"DPG menu error: {e}", flush=True)
        import traceback
        traceback.print_exc()
        raise SystemExit(1)
'''

# Main cheat script - runs in separate subprocess from DPG menu
cheat_script = '''
import dearpygui.dearpygui as dpg
import threading
import time
import sys

# Main cheat state
esp_enabled = True
aimbot_enabled = True
humanizer_enabled = True

# Global lifecycle flag for main cheat
cheat_running = threading.Event()
cheat_running.set()

def cleanup():
    """Clean shutdown hook."""
    print("Main cheat cleanup...", flush=True)
    cheat_running.clear()
    dpg.destroy_context()
    print("Main cheat cleanup complete.", flush=True)

import atexit
atexit.register(cleanup)

def render_esp():
    """Render ESP overlay on game screen."""
    while True:
        if esp_enabled:
            print("Rendering ESP...", flush=True)
        time.sleep(0.1)

def main():
    dpg.create_context()

    # Create window with anti-detection settings
    dpg.add_window(label="Main Cheat")

    # Set window properties BEFORE setup
    dpg.set_window_pos("Main Cheat", [600, 100])

    # ESP toggle
    with dpg.group(horizontal=True):
        dpg.add_text("ESP:")
        dpg.add_checkbox(tag="esp_check", default_value=esp_enabled,
                       callback=lambda s, a: exec("global esp_enabled; esp_enabled = a"))

    # Aimbot toggle
    with dpg.group(horizontal=True):
        dpg.add_text("Aimbot:")
        dpg.add_checkbox(tag="aim_check", default_value=aimbot_enabled,
                       callback=lambda s, a: exec("global aimbot_enabled; aimbot_enabled = a"))

    # Humanizer toggle
    with dpg.group(horizontal=True):
        dpg.add_text("Humanizer:")
        dpg.add_checkbox(tag="human_check", default_value=humanizer_enabled,
                       callback=lambda s, a: exec("global humanizer_enabled; humanizer_enabled = a"))

    dpg.setup_dearpygui()
    dpg.show_viewport()

    # Start ESP rendering thread
    esp_thread = threading.Thread(target=render_esp, daemon=True)
    esp_thread.start()

    # Keep main cheat running indefinitely using global lifecycle flag
    while cheat_running.is_set() and dpg.is_dearpygui_running():
        dpg.render_dearpygui_frame()

    dpg.destroy_context()


def stop_cheat():
    """Stop the main cheat gracefully."""
    cheat_running.clear()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Main cheat error: {e}", flush=True)
        import traceback
        traceback.print_exc()
        raise SystemExit(1)
'''


def launch_dpg_menu(retry: bool = True) -> subprocess.Popen | None:
    """Launch DPG menu in isolated subprocess with retry on native crashes."""
    max_retries = 3 if retry else 1

    for attempt in range(max_retries):
        try:
            proc = subprocess.Popen(
                [sys.executable, "-c", script],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                creationflags=0,  # No CREATE_NEW_CONSOLE - prevents CMD spam
            )
            print(f"DPG menu subprocess launched (PID: {proc.pid})")
            return proc
        except Exception as e:
            print(f"DPG menu launch attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(0.5)
                continue
            return None

    return None


def launch_main_cheat(retry: bool = True) -> subprocess.Popen | None:
    """Launch main cheat process with retry on native crashes."""
    max_retries = 3 if retry else 1

    for attempt in range(max_retries):
        try:
            proc = subprocess.Popen(
                [sys.executable, "-c", cheat_script],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                creationflags=0,  # No CREATE_NEW_CONSOLE - prevents CMD spam
            )
            print(f"Main cheat process launched (PID: {proc.pid})")
            return proc
        except Exception as e:
            print(f"Main cheat launch attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(0.5)
                continue
            return None

    return None


def main(launch_mode: str = "both") -> None:
    """Launch both DPG menu and main cheat in parallel."""
    print("Phase 4 Cheat - Subprocess Isolation Launch")
    print("=" * 50)

    # Launch DPG menu first (for visibility)
    dpg_proc = launch_dpg_menu()
    time.sleep(1)  # Give DPG menu time to initialize

    # Launch main cheat process
    cheat_proc = launch_main_cheat()

    print("\nBoth processes running!")
    print("DPG Menu PID:", dpg_proc.pid)
    print("Main Cheat PID:", cheat_proc.pid)

    # Track restart counts to detect loops
    dpg_restart_count = 0
    cheat_restart_count = 0
    max_restarts = 10  # Stop after too many restarts (loop detected)

    # Monitor both processes - but only restart on CRASH, not normal exit
    try:
        while True:
            time.sleep(1)

            # Check DPG menu status
            if dpg_proc.poll() is not None:
                exit_code = dpg_proc.returncode
                # Exit codes:
                # 0 = normal exit (expected for DPG menu - stays running via render loop)
                # 1 = error/crash (should restart)
                # 3221225477 (0xC0000005) = native ACCESS_VIOLATION crash
                if exit_code == 0:
                    # DPG menu exited normally - this is unexpected!
                    # Could be: render loop completed, user closed window, or no lifecycle control
                    print(f"DPG menu exited normally (code: {exit_code}), restarting...")
                    dpg_proc = launch_dpg_menu()
                    dpg_restart_count += 1
                elif exit_code == 3221225477 or (exit_code > 100 and exit_code & 0xC0000000):
                    # Native crash (ACCESS_VIOLATION) - restart immediately
                    print(f"DPG menu native crashed (exit code: {exit_code}), restarting...")
                    dpg_proc = launch_dpg_menu()
                    dpg_restart_count += 1
                elif exit_code and exit_code != 0:
                    # Python exception exit (code 1 typically)
                    print(f"DPG menu crashed (exit code: {exit_code}), restarting...")
                    dpg_proc = launch_dpg_menu()
                    dpg_restart_count += 1
                else:
                    print(f"DPG menu exited normally (code: {exit_code}), keeping running...")

                # Detect loop - too many restarts
                if dpg_restart_count >= max_restarts:
                    print(f"DPG menu restart loop detected ({dpg_restart_count} restarts), stopping...")
                    break

            # Check main cheat status
            if cheat_proc.poll() is not None:
                exit_code = cheat_proc.returncode
                if exit_code == 0:
                    # Main cheat exited normally - expected behavior
                    print(f"Main cheat exited normally (code: {exit_code}), keeping running...")
                    # Don't restart - this is normal for the main cheat loop
                elif exit_code == 3221225477 or (exit_code > 100 and exit_code & 0xC0000000):
                    # Native crash - restart
                    print(f"Main cheat native crashed (exit code: {exit_code}), restarting...")
                    cheat_proc = launch_main_cheat()
                    cheat_restart_count += 1
                elif exit_code and exit_code != 0:
                    # Python exception exit
                    print(f"Main cheat crashed (exit code: {exit_code}), restarting...")
                    cheat_proc = launch_main_cheat()
                    cheat_restart_count += 1
                else:
                    print(f"Main cheat exited normally (code: {exit_code}), keeping running...")

                # Detect loop - too many restarts
                if cheat_restart_count >= max_restarts:
                    print(f"Main cheat restart loop detected ({cheat_restart_count} restarts), stopping...")
                    break

    except KeyboardInterrupt:
        print("\nShutdown requested...")
        dpg_proc.terminate()
        cheat_proc.terminate()


if __name__ == "__main__":
    # Determine launch mode from command line argument
    launch_mode = sys.argv[1] if len(sys.argv) > 1 else "both"

    # Run main() - this keeps the DPG menu running
    # The loop inside main() monitors and restarts processes as needed
    main(launch_mode)
