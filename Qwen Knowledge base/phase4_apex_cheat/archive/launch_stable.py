#!/usr/bin/env python3
"""
Phase 4 Cheat - Simple Stable Launcher

Launches DPG menu and main cheat as separate Python files.
Uses file-based scripts for more stable subprocess execution.
"""

import subprocess
import sys
import time
from pathlib import Path


def launch_dpg_menu() -> subprocess.Popen:
    """Launch DPG menu subprocess."""
    script_path = Path(__file__).parent / "dpg_menu_stable.py"
    
    proc = subprocess.Popen(
        [sys.executable, str(script_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    print(f"[DPG Menu] Launched (PID: {proc.pid})")
    return proc


def launch_main_cheat() -> subprocess.Popen:
    """Launch main cheat subprocess."""
    script_path = Path(__file__).parent / "main_cheat_stable.py"
    
    proc = subprocess.Popen(
        [sys.executable, str(script_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
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
    print("Phase 4 Cheat - Stable Launcher")
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
