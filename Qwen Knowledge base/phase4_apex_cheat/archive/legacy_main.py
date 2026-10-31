#!/usr/bin/env python3
"""
Phase 4: Main Entry Point for Apex Cheat

Integrates cheat menu and ESP overlay with:
- INSERT key hotkey for visibility toggle
- Alt-tab window management
- Human baseline metrics tracking
- DPG subprocess isolation to avoid native crashes (0xC0000005)
"""

import ctypes
import signal
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from typing import Optional, Tuple

try:
    import dearpygui.dearpygui as dpg
    DPG_AVAILABLE = True
except ImportError:
    DPG_AVAILABLE = False
except Exception as e:
    # Native crash during import - DPG unavailable
    print(f"DPG import crashed (native): {e}")
    DPG_AVAILABLE = False

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

        # Initialize DPG context (per DPG 2.3.1 requirements)
        if DPG_AVAILABLE:
            # DPG 2.x uses is_viewport_ok() for context status
            if hasattr(dpg, 'is_viewport_ok'):
                if not dpg.is_viewport_ok():
                    dpg.create_context()
            elif hasattr(dpg, 'create_context'):
                # Fallback: just ensure context exists
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
            
        # INSERT key for menu toggle
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
        
        # Log the toggle for metrics
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
        # Get foreground window to detect game focus
        fg_hwnd = user32.GetForegroundWindow()
        
        if fg_hwnd:
            # Check if we're in Apex Legends
            class_name = ctypes.create_unicode_buffer(50)
            user32.GetClassNameW(fg_hwnd, class_name, 50)
            
            if "Apex" in class_name.value or "Origin" in class_name.value:
                # Game has focus - ensure ESP is visible
                if not self.esp_overlay.visible:
                    self.esp_overlay.show_after_alttab()
            else:
                # Not Apex - may be alt-tabbed away
                if self.config.enable_alttab_management and self.esp_overlay.visible:
                    self.esp_overlay.hide_for_alttab()
                    
    def on_kill(self) -> None:
        """Record a kill for human baseline metrics."""
        self.kills_count += 1
        
        # Decay accuracy after kill streak (per Phase 3 research)
        decay_factor = 1.0
        if self.kills_count > 8:
            # Exponential decay with τ ≈ 8-12 kills
            decay_factor = 1.0 - (self.kills_count / 12.0) * 0.1
            
        print(f"Kill recorded (streak: {self.kills_count}, accuracy factor: {decay_factor:.2f})")
        
    def stop(self) -> None:
        """Stop the cheat system."""
        self.running = False
        
        # Stop menu
        if hasattr(self.menu, 'running'):
            self.menu.running = False
            
        # Stop ESP overlay
        self.esp_overlay.enabled = False
        
        print(f"Apex Cheat Phase 4 stopped. Kills: {self.kills_count}")


def signal_handler(signum, frame) -> None:
    """Handle shutdown signals."""
    cheat.stop()


def launch_dpg_subprocess() -> Optional[subprocess.Popen]:
    """Launch DPG menu in subprocess to isolate native crashes."""
    try:
        script = '''
import dearpygui.dearpygui as dpg

def main():
    # Initialize context first (DPG 2.x requirement)
    dpg.create_context()
    
    # Create viewport with anti-detection settings
    dpg.create_viewport(
        title="Apex Cheat Menu",
        width=800,
        height=600,
        x_pos=100,
        y_pos=100,
        always_on_top=True,
        transparent_color=True
    )
    
    # Setup and show
    dpg.setup_dearpygui()
    dpg.show_viewport()
    
    # Main render loop
    while dpg.is_dearpygui_running():
        dpg.render_dearpygui_frame()
    
    dpg.destroy_context()

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"DPG menu error: {e}")
        raise SystemExit(1)
'''
        
        proc = subprocess.Popen(
            [sys.executable, "-c", script],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
        print(f"DPG menu subprocess launched (PID: {proc.pid})")
        return proc
    except Exception as e:
        print(f"Failed to launch DPG subprocess: {e}")
        return None


def main() -> None:
    """Main entry point for Phase 4 cheat system."""
    print("Starting Apex Cheat Phase 4...")
    
    # Try to launch DPG menu in subprocess (isolates native crashes)
    dpg_proc = None
    if DPG_AVAILABLE:
        try:
            dpg_proc = launch_dpg_subprocess()
        except Exception as e:
            print(f"DPG subprocess launch failed: {e}")

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
        # Start the cheat system (ESP, aimbot, humanizer - runs independently of DPG)
        cheat.start()
        print("Apex Cheat core started successfully")

        # Main update loop - continues even if DPG crashes
        while cheat.running:
            cheat.update_game_state()

            # Simulate kill events for testing
            dpg_running = (
                dpg_proc.poll() is None if dpg_proc 
                else (dpg.is_dearpygui_running() if DPG_AVAILABLE else True)
            )
            if cheat.kills_count < 30 and dpg_running:
                if cheat.kills_count > 0 and cheat.kills_count % 5 == 0:
                    cheat.on_kill()

            time.sleep(0.1)  # 10 Hz update rate

    except KeyboardInterrupt:
        pass
    finally:
        cheat.stop()
        
        # Clean up DPG subprocess if running
        if dpg_proc and dpg_proc.poll() is None:
            dpg_proc.terminate()
            print("DPG menu subprocess terminated")


if __name__ == "__main__":
    main()
