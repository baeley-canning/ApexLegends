#!/usr/bin/env python3
"""
Phase 4 Cheat Launcher

Launches DPG menu and main cheat with crash-resistant subprocess handling.
"""

import subprocess
import sys
import time
import threading


def launch_dpg_menu() -> subprocess.Popen:
    """Launch DPG menu subprocess."""
    script = '''
import dearpygui.dearpygui as dpg
import time
import sys

menu_running = True

def main():
    try:
        dpg.create_context()
        dpg.create_viewport(title="Apex Cheat Menu", width=500, height=400)
        dpg.set_viewport_always_on_top(True)
        dpg.set_viewport_visible(True)
        dpg.set_viewport_pos([100, 100])
        dpg.set_viewport_clear_color([26, 26, 46])
        dpg.setup_dearpygui()
        dpg.show_viewport()
        
        # Render loop
        while menu_running and dpg.is_dearpygui_running():
            dpg.render_dearpygui_frame()
            time.sleep(0.05)
    except Exception as e:
        print(f"DPG error: {e}", flush=True)
        raise SystemExit(1)

if __name__ == "__main__":
    main()
'''
    
    proc = subprocess.Popen(
        [sys.executable, "-c", script],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        creationflags=0,
    )
    print(f"[DPG Menu] Launched (PID: {proc.pid})")
    return proc


def launch_main_cheat() -> subprocess.Popen:
    """Launch main cheat subprocess."""
    script = '''
import dearpygui.dearpygui as dpg
import time
import threading

cheat_running = True

def render_esp():
    while cheat_running:
        print("ESP rendering...", flush=True)
        time.sleep(0.5)

def main():
    try:
        dpg.create_context()
        
        # Main window
        dpg.add_window(label="Main Cheat", width=400, height=300)
        dpg.set_window_pos("Main Cheat", 600, 100)
        
        # ESP toggle
        with dpg.group(horizontal=True):
            dpg.add_text("ESP: ")
            dpg.add_checkbox(default_value=True, tag="esp_check")
        
        # Aimbot toggle
        with dpg.group(horizontal=True):
            dpg.add_text("Aimbot: ")
            dpg.add_checkbox(default_value=True, tag="aim_check")
        
        dpg.setup_dearpygui()
        dpg.show_viewport()
        
        # ESP thread
        esp_thread = threading.Thread(target=render_esp, daemon=True)
        esp_thread.start()
        
        # Render loop
        while cheat_running and dpg.is_dearpygui_running():
            dpg.render_dearpygui_frame()
            time.sleep(0.05)
    except Exception as e:
        print(f"Cheat error: {e}", flush=True)
        raise SystemExit(1)

if __name__ == "__main__":
    main()
'''
    
    proc = subprocess.Popen(
        [sys.executable, "-c", script],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        creationflags=0,
    )
    print(f"[Main Cheat] Launched (PID: {proc.pid})")
    return proc


def monitor_process(proc: subprocess.Popen, name: str) -> bool:
    """Monitor a process and return True if it should be restarted."""
    exit_code = proc.returncode
    
    # Exit codes:
    # 0 = normal exit
    # 1 = Python exception
    # 3221225477 (0xC0000005) = native ACCESS_VIOLATION
    
    if exit_code == 0:
        print(f"[{name}] Exited normally (code: {exit_code}), restarting...")
        return True
    elif exit_code == 3221225477 or (exit_code > 100 and exit_code & 0xC0000000):
        print(f"[{name}] Native crash (code: {exit_code}), restarting...")
        return True
    elif exit_code != 0:
        print(f"[{name}] Crash (code: {exit_code}), restarting...")
        return True
    
    return False


def main():
    print("=" * 60)
    print("Phase 4 Cheat Launcher")
    print("=" * 60)
    
    dpg_proc = launch_dpg_menu()
    time.sleep(1)  # Give DPG time to initialize
    
    cheat_proc = launch_main_cheat()
    
    print("\nBoth processes running!")
    print(f"DPG Menu PID: {dpg_proc.pid}")
    print(f"Main Cheat PID: {cheat_proc.pid}")
    
    dpg_restarts = 0
    cheat_restarts = 0
    max_restarts = 15
    
    try:
        while True:
            time.sleep(1)
            
            # Check DPG menu
            if dpg_proc.poll() is not None:
                if monitor_process(dpg_proc, "DPG Menu"):
                    dpg_proc = launch_dpg_menu()
                    dpg_restarts += 1
                    if dpg_restarts >= max_restarts:
                        print(f"[DPG Menu] Restart limit reached ({dpg_restarts}), stopping...")
                        break
            
            # Check main cheat
            if cheat_proc.poll() is not None:
                if monitor_process(cheat_proc, "Main Cheat"):
                    cheat_proc = launch_main_cheat()
                    cheat_restarts += 1
                    if cheat_restarts >= max_restarts:
                        print(f"[Main Cheat] Restart limit reached ({cheat_restarts}), stopping...")
                        break
    
    except KeyboardInterrupt:
        print("\nShutdown requested...")
        dpg_proc.terminate()
        cheat_proc.terminate()
        print("Done.")


if __name__ == "__main__":
    main()
