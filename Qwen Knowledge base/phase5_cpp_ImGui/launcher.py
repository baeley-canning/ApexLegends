#!/usr/bin/env python3
"""
Launcher for Phase 5 Apex Cheat (C++ ImGui with D3D11)

Follows user preference: launch cheat first, then Apex.
This ensures the C++ DLL menu and ESP overlay are ready before game starts.

Usage:
    python launcher.py [--cheat-only] [--game-only] [--both]
"""

import os
import subprocess
import sys
import time
from pathlib import Path


# Paths (adjust these to your setup)
CHEAT_DIR = Path(r"C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase5_cpp_ImGui")
APEX_PATH = Path(r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe")


def print_header(text: str) -> None:
    """Print a formatted header."""
    if sys.platform == 'win32':
        try:
            print(f"\n{'=' * 60}")
            print(f"  {text}")
            print(f"{'=' * 60}\n")
        except UnicodeEncodeError:
            print(f"\n{'=' * 60}")
            print(f"  {text}")
            print(f"{'=' * 60}\n")
    else:
        print(f"\n{'=' * 60}")
        print(f"  {text}")
        print(f"{'=' * 60}\n")


def print_success(text: str) -> None:
    """Print success message with compatible checkmark."""
    if sys.platform == 'win32':
        print(f"[OK] {text}")
    else:
        print(f"\u2713 {text}")


def launch_cheat() -> subprocess.Popen:
    """Launch the C++ ImGui cheat menu (internal overlay, Kernaim/Ignite/Chudvision pattern)."""
    print_header("Launching Apex Cheat Phase 5 (C++ D3D11)")

    # Start the C++ DLL menu
    # The DLL should be built first: msbuild apex_cheat.sln /p:Configuration=Release
    creation_flags = subprocess.CREATE_NO_WINDOW if sys.platform == 'win32' else 0
    
    # Launch Python wrapper which loads apex_cheat.dll
    menu_process = subprocess.Popen(
        [sys.executable, str(CHEAT_DIR / "python_wrapper" / "apex_cheat_py.py")],
        cwd=str(CHEAT_DIR),
        creationflags=creation_flags,
    )

    print(f"Cheat menu PID: {menu_process.pid}")
    print("Waiting for menu to initialize...")

    # Give the menu time to start
    time.sleep(2)

    print_success("Cheat menu launched successfully")
    return menu_process


def launch_apex() -> subprocess.Popen:
    """Launch Apex Legends."""
    print_header("Launching Apex Legends")

    if not APEX_PATH.exists():
        try:
            print(f"WARNING: Apex not found at: {APEX_PATH}")
        except UnicodeEncodeError:
            print(f"[WARN] Apex not found at: {APEX_PATH}")
        print("Please update APEX_PATH in launcher.py")
        return None

    # Start Apex with CREATE_NO_WINDOW to suppress console spam
    creation_flags = subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP
    apex_process = subprocess.Popen(
        [str(APEX_PATH)],
        cwd=str(APEX_PATH.parent),
        creationflags=creation_flags,
    )

    print(f"Apex PID: {apex_process.pid}")
    print_success("Apex Legends launched successfully")

    return apex_process


def launch_both() -> tuple[subprocess.Popen, subprocess.Popen]:
    """Launch both cheat and Apex in sequence."""
    menu_process = launch_cheat()
    time.sleep(1)  # Small delay between cheat and game
    apex_process = launch_apex()

    return menu_process, apex_process


def wait_for_processes(*processes: subprocess.Popen) -> None:
    """Wait for all processes to complete."""
    print_header("Monitoring Processes")

    try:
        for proc in processes:
            if proc:
                proc.wait()
    except KeyboardInterrupt:
        print("\nShutdown requested...")
    finally:
        for proc in processes:
            if proc and proc.poll() is None:
                proc.terminate()


def main() -> None:
    """Main entry point."""
    print_header("Apex Cheat Phase 5 Launcher (C++ D3D11)")

    # Parse command line arguments
    mode = sys.argv[1] if len(sys.argv) > 1 else "--both"

    if mode == "--cheat-only":
        menu_process = launch_cheat()
        wait_for_processes(menu_process)

    elif mode == "--game-only":
        apex_process = launch_apex()
        wait_for_processes(apex_process)

    elif mode == "--both":
        menu_process, apex_process = launch_both()
        wait_for_processes(menu_process, apex_process)

    else:
        print(f"Unknown mode: {mode}")
        print("Usage: python launcher.py [--cheat-only | --game-only | --both]")
        sys.exit(1)


if __name__ == "__main__":
    main()
