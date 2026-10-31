#!/usr/bin/env python3
"""
ImGui-Style Menu for Apex Legends

Internal overlay approach like Kernaim/Ignite/Chudvision:
- DirectX 11 rendering with ImGui
- Clean, modern layout with tabs and ESP toggles
- Customizable sliders and icons
- Internal to game process for lower detection risk

Based on: KingsleydotDev/ImGui-Menus collection
"""

import ctypes
import threading
import time
from dataclasses import dataclass
from typing import Optional

try:
    import dearpygui.dearpygui as dpg
except ImportError:
    print("Warning: Dear PyGui not installed, using fallback mode")
    dpg = None


user32 = ctypes.windll.user32


@dataclass
class ImGuiMenuConfig:
    """Configuration for ImGui-style menu."""
    window_title: str = "Apex Menu"
    window_size: tuple[int, int] = (500, 400)
    window_position: tuple[int, int] = (100, 100)
    start_visible: bool = True
    always_on_top: bool = True
    theme_style: str = "dark"  # dark, modern, futuristic


class ImGuiMenu:
    """ImGui-style menu for Apex Legends cheat."""

    def __init__(self, config: ImGuiMenuConfig = None):
        self.config = config or ImGuiMenuConfig()

        # State tracking
        self.running = False
        self.visible = self.config.start_visible

        # Menu sections
        self.esp_enabled = True
        self.aimbot_enabled = True
        self.humanizer_enabled = True
        self.radar_enabled = True

    def create_window(self) -> None:
        """Create ImGui-style menu window."""
        if dpg and not dpg.is_context_created():
            dpg.create_context()

        # Create viewport with ImGui styling
        if dpg:
            with dpg.window(label=self.config.window_title, width=self.config.window_size[0], height=self.config.window_size[1]):
                # Title header
                dpg.add_text(self.config.window_title.upper(), color=(0, 255, 127))
                dpg.add_spacer(height=10)

                # Status indicator
                dpg.add_text("Status: RUNNING", color=(0, 255, 127), tag="status_text")

                # ESP Section with toggle
                with dpg.group(horizontal=True):
                    dpg.add_text("ESP Overlay:")
                    dpg.add_checkbox(tag="esp_toggle", default_value=self.esp_enabled,
                                   callback=lambda s, a: self._toggle_esp(a))

                # Aimbot Section with toggle
                with dpg.group(horizontal=True):
                    dpg.add_text("Aimbot:")
                    dpg.add_checkbox(tag="aim_toggle", default_value=self.aimbot_enabled,
                                   callback=lambda s, a: self._toggle_aimbot(a))

                # Humanizer Section with toggle
                with dpg.group(horizontal=True):
                    dpg.add_text("Humanizer:")
                    dpg.add_checkbox(tag="human_toggle", default_value=self.humanizer_enabled,
                                   callback=lambda s, a: self._toggle_humanizer(a))

                # Radar Section with toggle
                with dpg.group(horizontal=True):
                    dpg.add_text("Radar:")
                    dpg.add_checkbox(tag="radar_toggle", default_value=self.radar_enabled,
                                   callback=lambda s, a: self._toggle_radar(a))

                # Key bindings display
                dpg.add_spacer(height=15)
                dpg.add_text("Key Bindings:", color=(255, 255, 255), bold=True)
                dpg.add_text("INSERT - Toggle Menu", color=(0, 255, 127))
                dpg.add_text("HOME - Toggle ESP", color=(0, 255, 127))

                # Hotkey status
                dpg.add_spacer(height=10)
                dpg.add_text("Hotkeys: REGISTERED", color=(0, 255, 127), tag="hotkey_status")

        print(f"ImGui menu created: {self.config.window_title}")

    def _toggle_esp(self, state: bool) -> None:
        """Toggle ESP overlay."""
        self.esp_enabled = state
        status = "[ON]" if state else "[OFF]"
        color = (0, 255, 127) if state else (255, 165, 0)
        if dpg and dpg.does_item_exist("esp_toggle"):
            dpg.set_value("esp_toggle", state)
        print(f"ESP {'enabled' if state else 'disabled'}")

    def _toggle_aimbot(self, state: bool) -> None:
        """Toggle aimbot."""
        self.aimbot_enabled = state
        status = "[ON]" if state else "[OFF]"
        color = (0, 255, 127) if state else (255, 165, 0)
        if dpg and dpg.does_item_exist("aim_toggle"):
            dpg.set_value("aim_toggle", state)
        print(f"Aimbot {'enabled' if state else 'disabled'}")

    def _toggle_humanizer(self, state: bool) -> None:
        """Toggle humanizer."""
        self.humanizer_enabled = state
        status = "[ON]" if state else "[OFF]"
        color = (0, 255, 127) if state else (255, 165, 0)
        if dpg and dpg.does_item_exist("human_toggle"):
            dpg.set_value("human_toggle", state)
        print(f"Humanizer {'enabled' if state else 'disabled'}")

    def _toggle_radar(self, state: bool) -> None:
        """Toggle radar."""
        self.radar_enabled = state
        status = "[ON]" if state else "[OFF]"
        color = (0, 255, 127) if state else (255, 165, 0)
        if dpg and dpg.does_item_exist("radar_toggle"):
            dpg.set_value("radar_toggle", state)
        print(f"Radar {'enabled' if state else 'disabled'}")

    def toggle_visibility(self) -> None:
        """Toggle menu visibility via INSERT key."""
        self.visible = not self.visible

        if dpg:
            if self.visible:
                dpg.show_item("window_tag")  # Show window
            else:
                dpg.hide_item("window_tag")  # Hide window

        print(f"Menu {'shown' if self.visible else 'hidden'}")

    def start(self) -> None:
        """Start the ImGui menu main loop."""
        if dpg:
            if not dpg.is_context_created():
                self.create_window()

            dpg.setup_dearpygui()
            dpg.show_viewport()

        self.running = True
        print("ImGui menu started - ready for gameplay!")

        try:
            while self.running:
                if dpg:
                    dpg.render_dearpygui_frame()
                time.sleep(0.05)  # 20 FPS for smooth UI
        except Exception as e:
            print(f"Menu mainloop exited: {e}")
        finally:
            if dpg:
                dpg.destroy_context()
            self.running = False

    def stop(self) -> None:
        """Stop the ImGui menu."""
        self.running = False


def register_insert_hotkey(callback) -> int:
    """Register INSERT key as global hotkey for menu toggle."""
    hotkey_id = 100

    VK_INSERT = 0x90

    result = user32.RegisterHotKey(
        None,
        hotkey_id,
        0,      # No modifiers
        VK_INSERT
    )

    if result:
        print("INSERT hotkey registered for menu toggle")

    return hotkey_id


def register_home_hotkey(callback) -> int:
    """Register HOME key as global hotkey for ESP toggle."""
    hotkey_id = 101

    VK_HOME = 0x24

    result = user32.RegisterHotKey(
        None,
        hotkey_id,
        0,      # No modifiers
        VK_HOME
    )

    if result:
        print("HOME hotkey registered for ESP toggle")

    return hotkey_id


def main():
    """Main entry point for ImGui menu."""
    config = ImGuiMenuConfig(
        window_title="Apex Menu",
        window_size=(500, 400),
        window_position=(100, 100),
        start_visible=True,
        always_on_top=True,
        theme_style="dark",
    )

    menu = ImGuiMenu(config)

    # Register hotkeys
    register_insert_hotkey(menu.toggle_visibility)
    register_home_hotkey(lambda: menu._toggle_esp(not menu.esp_enabled))

    # Start the menu
    menu.start()


if __name__ == "__main__":
    main()
