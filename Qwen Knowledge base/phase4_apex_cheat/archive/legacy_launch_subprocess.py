#!/usr/bin/env python3
"""
Phase 4: Launch cheat with DPG subprocess isolation

This launcher runs the main cheat process in a subprocess to avoid
native crashes (0xC0000005) from _dearpygui.pyd during import.
"""

import subprocess
import sys
import time


CHEAT_DIR = r"C:\Users\New User\OneDrive\Desktop\Qwen Knowledge base\phase4_apex_cheat"


def main():
    """Launch cheat in subprocess to isolate DPG native crashes."""
    script = '''
import sys
sys.path.insert(0, r"''' + CHEAT_DIR + r'''")

import ctypes
import signal
import threading
import time
from dataclasses import dataclass
from typing import Optional

# Import with crash protection for DPG
DPG_AVAILABLE = False
dpg = None

try:
    import dearpygui.dearpygui as dpg
    DPG_AVAILABLE = True
except Exception as e:
    print(f"DPG import skipped: {e}")

from cheat_menu import CheatMenu, MenuConfig, register_insert_hotkey
from esp_overlay import ESPOverlay, ESPConfig, PlayerInfo, create_external_overlay

# Windows API constants
VK_INSERT = 0x90
VK_HOME = 0x24
user32 = ctypes.windll.user32


@dataclass
class CheatConfig:
    """Configuration for the complete cheat system."""
    menu_config: MenuConfig = None
    esp_config: ESPConfig = None
    enable_insert_hotkey: bool = True
    enable_alttab_management: bool = True
    enable_humanizer: bool = True


class ApexCheat:
    """Main cheat system integrating menu and ESP overlay."""

    def __init__(self, config: CheatConfig = None):
        self.config = config or CheatConfig()

        # Initialize components
        self.menu = CheatMenu(self.config.menu_config)
        self.esp_overlay = ESPOverlay(self.config.esp_config)

        # State tracking
        self.running = False
        self.start_time = 0.0
        self.kills_count = 0

        # Human baseline metrics (from Phase 3 research)
        self.reaction_times: list[float] = []
        self.micro_jitter: float = 1.5  # degrees at 60Hz

    def start(self) -> None:
        """Start the complete cheat system."""
        print("Starting Apex Cheat Phase 4...")

        # Initialize DPG context if available
        if DPG_AVAILABLE:
            if hasattr(dpg, 'is_viewport_ok'):
                if not dpg.is_viewport_ok():
                    dpg.create_context()
            elif hasattr(dpg, 'create_context'):
                if not dpg.is_context_created() if hasattr(dpg, 'is_context_created') else True:
                    dpg.create_context()

        # Start menu
        self.menu.start()

        # Start ESP overlay
        self.esp_overlay.enabled = True

        # Register INSERT hotkey if enabled
        if self.config.enable_insert_hotkey:
            self._register_hotkeys()

        # Set running state
        self.running = True
        self.start_time = time.time()

        print("Apex Cheat Phase 4 started successfully")

    def _register_hotkeys(self) -> None:
        """Register global hotkeys for menu toggle."""
        if not DPG_AVAILABLE:
            return

        user32.RegisterHotKey.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_uint,
            ctypes.c_uint
        ]

        # Register INSERT key (VK_INSERT = 0x90)
        result = user32.RegisterHotKey(
            None,
            100,  # hotkey_id
            0,    # no modifiers
            VK_INSERT
        )

        if result:
            print("INSERT hotkey registered for menu toggle")

        # Also register HOME key as alternative
        result = user32.RegisterHotKey(
            None,
            101,  # hotkey_id
            0,
            VK_HOME
        )

        if result:
            print("HOME hotkey registered as alternative")

    def toggle_menu_visibility(self) -> None:
        """Toggle menu visibility via INSERT key."""
        self.menu.toggle_visibility()

        if self.config.enable_humanizer:
            self._record_toggle_event("menu", self.menu.visible)

        print(f"Menu {'shown' if self.menu.visible else 'hidden'}")

    def toggle_esp_visibility(self) -> None:
        """Toggle ESP overlay visibility."""
        self.esp_overlay.toggle_visibility()

        if self.config.enable_humanizer:
            self._record_toggle_event("esp", self.esp_overlay.visible)

        print(f"ESP {'shown' if self.esp_overlay.visible else 'hidden'}")

    def _record_toggle_event(self, component: str, visible: bool) -> None:
        """Record toggle event for human baseline metrics."""
        elapsed = time.time() - self.start_time
        self.reaction_times.append(elapsed)

    def update_game_state(self) -> None:
        """Update cheat state based on game conditions."""
        if not self.running:
            return

        # Update ESP overlay
        self.esp_overlay.update()

        # Check for alt-tab transition if enabled
        if self.config.enable_alttab_management:
            self._check_alttab_state()

    def _check_alttab_state(self) -> None:
        """Check and respond to alt-tab window state."""
        fg_hwnd = user32.GetForegroundWindow()

        if fg_hwnd:
            class_name = ctypes.create_unicode_buffer(50)
            user32.GetClassNameW(fg_hwnd, class_name, 50)

            if "Apex" in class_name.value or "Origin" in class_name.value:
                if not self.esp_overlay.visible:
                    self.esp_overlay.show_after_alttab()
            else:
                if self.config.enable_alttab_management and self.esp_overlay.visible:
                    self.esp_overlay.hide_for_alttab()

    def on_kill(self) -> None:
        """Record a kill for human baseline metrics."""
        self.kills_count += 1

        decay_factor = 1.0
        if self.kills_count > 8:
            decay_factor = 1.0 - (self.kills_count / 12.0) * 0.1

        print(f"Kill recorded (streak: {self.kills_count}, accuracy factor: {decay_factor:.2f})")

    def stop(self) -> None:
        """Stop the cheat system."""
        self.running = False

        if hasattr(self.menu, 'running'):
            self.menu.running = False

        self.esp_overlay.enabled = False

        print(f"Apex Cheat Phase 4 stopped. Kills: {self.kills_count}")


def signal_handler(signum, frame) -> None:
    """Handle shutdown signals."""
    cheat.stop()


def main() -> None:
    """Main entry point for Phase 4 cheat system."""
    # Configure cheat system
    menu_config = MenuConfig(
        window_title="Apex Cheat Menu",
        window_size=(800, 600),
        window_position=(100, 100),
        start_visible=True,
    )

    esp_config = ESPConfig(
        enabled=True,
        show_names=True,
        show_distance=True,
        show_health=True,
        show_angles=True,
        show_aim_spots=True,
        hide_on_alttab=True,
    )

    cheat_config = CheatConfig(
        menu_config=menu_config,
        esp_config=esp_config,
        enable_insert_hotkey=True,
        enable_alttab_management=True,
        enable_humanizer=True,
    )

    # Initialize cheat system
    global cheat
    cheat = ApexCheat(cheat_config)

    # Set up signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    try:
        # Start the cheat system
        cheat.start()

        # Main update loop
        while cheat.running:
            cheat.update_game_state()

            # Simulate kill events for testing
            dpg_running = (
                dpg.is_dearpygui_running() if DPG_AVAILABLE else True
            )
            if cheat.kills_count < 30 and dpg_running:
                if cheat.kills_count > 0 and cheat.kills_count % 5 == 0:
                    cheat.on_kill()

            time.sleep(0.1)  # 10 Hz update rate

    except KeyboardInterrupt:
        pass
    finally:
        cheat.stop()


if __name__ == "__main__":
    main()
'''

    print("Launching Apex Cheat Phase 4 (subprocess isolated)...")
    print("=" * 60)

    proc = subprocess.Popen(
        [sys.executable, "-c", script],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        cwd=CHEAT_DIR,
    )

    # Monitor output
    try:
        for line in proc.stdout:
            print(line, end='')  # line already has newline
    except KeyboardInterrupt:
        pass
    finally:
        proc.wait()
        print("=" * 60)
        print(f"Exit code: {proc.returncode}")


if __name__ == "__main__":
    main()
