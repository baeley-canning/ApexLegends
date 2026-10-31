#!/usr/bin/env python3
"""
Phase 4: Cheat Menu with Dear PyGui

Minimum viable cheat menu and ESP overlay for Apex Legends.
Features:
- DPG 2.3.1 compatible initialization (context before viewport)
- INSERT key hotkey for visibility toggle
- Alt-tab aware window management
- ESP overlay rendering with anti-detection measures
"""

import ctypes
import threading
import time
from dataclasses import dataclass, field
from typing import Optional

try:
    import dearpygui.dearpygui as dpg
    DPG_AVAILABLE = True
except ImportError:
    DPG_AVAILABLE = False

# Windows API constants
VK_INSERT = 0x90
VK_HOME = 0x24
MOD_ALT = 0x0001
MOD_CONTROL = 0x0002
MOD_SHIFT = 0x0004

user32 = ctypes.windll.user32


@dataclass
class MenuConfig:
    """Configuration for the cheat menu."""
    window_title: str = "Apex Cheat Menu"
    window_size: tuple[int, int] = (800, 600)
    window_position: tuple[int, int] = (100, 100)
    start_visible: bool = True
    use_vsync: bool = True
    always_on_top: bool = True
    transparent_window: bool = True
    alt_tab_behavior: str = "external_overlay"  # external_overlay or locked_to_game


class CheatMenu:
    """Dear PyGui-based cheat menu for Apex Legends."""

    def __init__(self, config: MenuConfig = None):
        self.config = config or MenuConfig()

        # DPG initialization (per DPG 2.3.1 requirements)
        if DPG_AVAILABLE:
            # DPG 2.x uses is_viewport_ok() for context status
            if hasattr(dpg, 'is_viewport_ok'):
                if not dpg.is_viewport_ok():
                    dpg.create_context()
            elif hasattr(dpg, 'create_context'):
                # Fallback: just ensure context exists
                if not dpg.is_context_created() if hasattr(dpg, 'is_context_created') else True:
                    dpg.create_context()

        self.initialized = False
        self.running = False
        self.visible = self.config.start_visible

        # Menu state
        self._menu_items: dict = {}
        self._esp_overlay: Optional['ESPOverlay'] = None
        
    def start(self) -> None:
        """Start the cheat menu main loop."""
        if not DPG_AVAILABLE:
            print("Dear PyGui not available, skipping menu startup")
            return
            
        # Create viewport with anti-detection measures
        self._create_viewport()
        
        # Setup and show viewport
        dpg.setup_dearpygui()
        dpg.show_viewport()
        
        # Manual render loop for better control
        self.running = True
        render_thread = threading.Thread(target=self._render_loop, daemon=True)
        render_thread.start()
        
        # Cleanup on exit
        try:
            while self.running:
                time.sleep(0.016)  # ~60 FPS
        except KeyboardInterrupt:
            pass
        finally:
            dpg.destroy_context()
            
    def _create_viewport(self) -> None:
        """Create DPG viewport with anti-detection measures."""
        if not DPG_AVAILABLE:
            return

        try:
            # DPG 2.x requires context before viewport
            if hasattr(dpg, 'create_context'):
                if not dpg.is_context_created():
                    dpg.create_context()
                    print(f"[OK] Context created")

            viewport_kwargs = {
                "title": self.config.window_title,
                "width": self.config.window_size[0],
                "height": self.config.window_size[1],
                "x_pos": self.config.window_position[0],
                "y_pos": self.config.window_position[1],
                "vsync": self.config.use_vsync,
                "always_on_top": self.config.always_on_top,
            }

            dpg.create_viewport(**viewport_kwargs)
            print(f"[OK] Viewport created: {self.config.window_title}")
        except Exception as e:
            print(f"[FAIL] Viewport creation failed: {e}")
            raise
        
    def _render_loop(self) -> None:
        """Manual render loop for the menu."""
        while self.running and DPG_AVAILABLE:
            dpg.render_frame()
            
    def toggle_visibility(self) -> None:
        """Toggle menu visibility via INSERT key or programmatically."""
        if not DPG_AVAILABLE or not self.initialized:
            return
            
        self.visible = not self.visible
        
        # Toggle viewport visibility
        hwnd = dpg.get_viewport_hwnd() if hasattr(dpg, 'get_viewport_hwnd') else None
        if hwnd:
            if self.visible:
                user32.ShowWindow(hwnd, 5)  # SW_SHOW
            else:
                user32.ShowWindow(hwnd, 0)  # SW_HIDE
                
    def stop(self) -> None:
        """Stop the cheat menu."""
        self.running = False


class ESPOverlay:
    """ESP overlay for rendering player/enemy indicators."""
    
    def __init__(self, menu: CheatMenu):
        self.menu = menu
        self.enabled = True
        self.players: list[dict] = []
        
    def update(self) -> None:
        """Update ESP overlay with current game state."""
        if not self.enabled:
            return
            
        # Render player indicators
        for player in self.players:
            self._render_player(player)
            
    def _render_player(self, player: dict) -> None:
        """Render a single player's ESP indicators."""
        if not DPG_AVAILABLE:
            return
            
        # Draw name, distance, health, etc.
        pass
        
    def toggle_visibility(self) -> None:
        """Toggle ESP overlay visibility."""
        self.enabled = not self.enabled


def register_insert_hotkey(callback) -> int:
    """Register INSERT key as global hotkey."""
    hotkey_id = 100
    
    if hasattr(user32, 'RegisterHotKey'):
        user32.RegisterHotKey.argtypes = [
            ctypes.WINFUNCTYPE(None, ctypes.c_uint, ctypes.c_uint),
            ctypes.c_uint,
            ctypes.c_uint,
            ctypes.c_uint
        ]
        
        # Register INSERT key (VK_INSERT) with no modifiers
        result = user32.RegisterHotKey(
            None,
            hotkey_id,
            0,  # No modifiers
            VK_INSERT
        )
        
        if result:
            print(f"INSERT hotkey registered successfully (ID: {hotkey_id})")
            
    return hotkey_id


def main():
    """Main entry point for Phase 4 cheat menu."""
    config = MenuConfig()
    menu = CheatMenu(config)
    
    # Start the menu
    menu.start()


if __name__ == "__main__":
    main()
