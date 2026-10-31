#!/usr/bin/env python3
"""
Phase 4: Apex Cheat Launcher

Launches the cheat DLL and sets up basic menu/ESP overlay.
Follows user preference: launch cheat first, then Apex.

USAGE:
    python launcher.py              # Just load cheat + hotkeys (no auto-launch Apex)
    python launcher.py --apex       # Also launch Apex after cheat loads
    python launcher.py --menu       # Launch DPG menu instead of just DLL
"""

import ctypes
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Optional

# Windows API constants
VK_INSERT = 0x90
VK_HOME = 0x24
MOD_ALT = 0x0001
MOD_CONTROL = 0x0002
MOD_SHIFT = 0x0004

user32 = ctypes.windll.user32


# Unicode checkmark for compatibility with Windows console encoding
def checkmark():
    """Return checkmark character compatible with Windows console."""
    return "[OK]"


def cm():
    """Convenience alias for checkmark - returns compatible string for Windows console."""
    return "[OK]"


def log(msg):
    """Print message with checkmark, handling Windows console encoding."""
    print(f"[OK] {msg}")


@dataclass
class CheatConfig:
    """Configuration for the Apex cheat."""
    dll_path: str = r"C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase4_apex_cheat_package\apex_cheat.dll"
    apex_path: str = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
    menu_visible: bool = True
    esp_visible: bool = True
    aimbot_enabled: bool = True


class ApexCheat:
    """Apex Legends cheat manager."""

    def __init__(self, config: CheatConfig = None):
        self.config = config or CheatConfig()
        self.dll_handle = None
        self.menu_visible = self.config.menu_visible
        self.esp_visible = self.config.esp_visible
        self.aimbot_enabled = self.config.aimbot_enabled

    def load_dll(self) -> bool:
        """Load the cheat DLL."""
        try:
            if os.path.exists(self.config.dll_path):
                self.dll_handle = ctypes.WinDLL(self.config.dll_path)
                print(f"[OK] Loaded {self.config.dll_path}")
                return True
            else:
                print(f"[FAIL] DLL not found: {self.config.dll_path}")
                print(f"       Looking for DLL at: {self.config.dll_path}")
                return False
        except Exception as e:
            print(f"[FAIL] Failed to load DLL: {e}")
            return False

    def toggle_menu(self) -> None:
        """Toggle menu visibility via hotkey or API."""
        self.menu_visible = not self.menu_visible
        status = "[VISIBLE]" if self.menu_visible else "[HIDDEN]"
        print(f"Menu {status}")

    def toggle_esp(self) -> None:
        """Toggle ESP overlay visibility."""
        self.esp_visible = not self.esp_visible
        status = "[VISIBLE]" if self.esp_visible else "[HIDDEN]"
        print(f"ESP {status}")

    def toggle_aimbot(self) -> None:
        """Toggle aimbot on/off."""
        self.aimbot_enabled = not self.aimbot_enabled
        status = "[ENABLED]" if self.aimbot_enabled else "[DISABLED]"
        print(f"Aimbot {status}")


def register_hotkeys() -> list[int]:
    """Register global hotkeys for cheat controls."""
    hotkey_ids = []

    # INSERT key - toggle menu
    result = user32.RegisterHotKey(
        None,
        100,  # hotkey_id
        0,    # no modifiers
        VK_INSERT
    )
    if result:
        hotkey_ids.append(100)
        print(f"[OK] INSERT hotkey registered (ID: 100)")
    else:
        print(f"[FAIL] Failed to register INSERT hotkey")

    # HOME key - toggle ESP
    result = user32.RegisterHotKey(
        None,
        101,  # hotkey_id
        0,    # no modifiers
        VK_HOME
    )
    if result:
        hotkey_ids.append(101)
        print(f"[OK] HOME hotkey registered (ID: 101)")
    else:
        print(f"[FAIL] Failed to register HOME hotkey")

    return hotkey_ids


def launch_apex(auto_launch: bool = True) -> Optional[subprocess.Popen]:
    """Launch Apex Legends."""
    if not auto_launch:
        print("[SKIP] Auto-launch Apex disabled (use --apex flag)")
        return None

    apex_paths = [
        r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe",
        r"C:\Program Files\EA Games\Apex\ApexLegends.exe",
        r"C:\Program Files (x86)\EA Games\Apex Legends\ApexLegends.exe",
    ]

    for apex_path in apex_paths:
        if os.path.exists(apex_path):
            print(f"[LAUNCHING] Apex: {apex_path}")
            process = subprocess.Popen([apex_path])
            time.sleep(2)  # Wait for Apex to start
            print("[OK] Apex launched")
            return process

    print(f"[FAIL] Apex not found. Searched: {', '.join(apex_paths)}")
    print("       Launch Apex manually or use --apex-path <path>")
    return None


def launch_dpg_menu() -> Optional[subprocess.Popen]:
    """Launch Dear PyGui menu subprocess."""
    try:
        import dearpygui.dearpygui as dpg
        print("[OK] DPG available, launching menu...")
        
        # Import and run the menu
        from cheat_menu import CheatMenu, MenuConfig
        
        config = MenuConfig()
        menu = CheatMenu(config)
        
        # Start the menu in a thread
        import threading
        menu_thread = threading.Thread(target=menu.start, daemon=True)
        menu_thread.start()
        
        print("[OK] DPG menu launched")
        return None  # DPG runs in background
    except ImportError:
        print("[FAIL] DPG not installed. Run: pip install dearpygui")
        return None
    except Exception as e:
        print(f"[FAIL] Failed to launch DPG menu: {e}")
        return None


def print_usage():
    """Print usage information."""
    print("\nUSAGE:")
    print("  python launcher.py              # Load cheat + hotkeys only")
    print("  python launcher.py --apex       # Also launch Apex after cheat")
    print("  python launcher.py --menu       # Launch DPG menu (Dear PyGui)")
    print("  python launcher.py --both       # Launch both menu and Apex")
    print()


def main():
    """Main entry point."""
    print("=" * 60)
    print("Apex Legends Cheat - Phase 4 Launcher")
    print("=" * 60)
    print()

    # Parse command line arguments
    auto_launch_apex = "--apex" in sys.argv or "--both" in sys.argv
    launch_menu = "--menu" in sys.argv or "--both" in sys.argv

    # Configuration
    config = CheatConfig()

    # Create cheat instance
    cheat = ApexCheat(config)

    # Step 1: Load cheat DLL (cheat first, per user preference)
    print("[Step 1] Loading cheat DLL...")
    if not cheat.load_dll():
        print("Warning: DLL load failed, continuing anyway...")
    print()

    # Step 2: Register hotkeys
    print("[Step 2] Registering hotkeys...")
    hotkey_ids = register_hotkeys()
    print()

    # Step 3: Launch DPG menu if requested
    if launch_menu:
        print("[Step 3] Launching DPG menu...")
        launch_dpg_menu()
        print()

    # Step 4: Launch Apex if requested
    if auto_launch_apex:
        print("[Step 4] Launching Apex Legends...")
        apex_process = launch_apex(auto_launch=True)
        print()
    else:
        print("[SKIP] Auto-launch Apex disabled")
        print("       Run: python launcher.py --apex to launch Apex automatically")
        print()

    # Summary
    print("=" * 60)
    print("Cheat Status:")
    print(f"  Menu:  {'[VISIBLE]' if cheat.menu_visible else '[HIDDEN]'}")
    print(f"  ESP:   {'[VISIBLE]' if cheat.esp_visible else '[HIDDEN]'}")
    print(f"  Aimbot: {'[ENABLED]' if cheat.aimbot_enabled else '[DISABLED]'}")
    print()
    print("Hotkeys:")
    print("  INSERT - Toggle Menu")
    print("  HOME   - Toggle ESP")
    print("=" * 60)
    print()

    if launch_menu:
        print("[DONE] Cheat is ready! DPG menu should be visible.")
        print("       Press INSERT to toggle menu visibility.")
    elif auto_launch_apex:
        print("[DONE] Cheat is ready! Apex should be launching...")
    else:
        print("[DONE] Cheat is ready!")
        print("       Press INSERT to toggle menu.")
        print("       Run with --apex to launch Apex automatically.")

    # Keep running if we launched something
    try:
        if auto_launch_apex and apex_process:
            apex_process.wait()
        else:
            # Just wait for user input or Ctrl+C
            input("Press Enter to exit...")
    except KeyboardInterrupt:
        print("\nShutting down cheat...")

    return 0


if __name__ == "__main__":
    sys.exit(main())
