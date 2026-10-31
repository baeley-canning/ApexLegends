#!/usr/bin/env python3
"""
External Tkinter Menu for Apex Cheat

Designed for low detection risk with Javelin anti-cheat:
- External process (not injected)
- Simple window classes (easier to randomize/spoof)
- Independent positioning (not locked to game window)
- INSERT key toggle for visibility management
"""

import ctypes
import threading
import time
import tkinter as tk
from dataclasses import dataclass, field
from typing import Optional

user32 = ctypes.windll.user32


@dataclass
class MenuConfig:
    """Configuration for external Tkinter menu."""
    window_title: str = "Apex Cheat Menu"
    window_size: tuple[int, int] = (700, 500)
    window_position: tuple[int, int] = (50, 50)
    start_visible: bool = True
    always_on_top: bool = True
    transparent_background: bool = True
    custom_window_class: str = "ApexCheatMenu"
    use_vsync: bool = True


class ExternalMenu:
    """External Tkinter menu for Apex Legends cheat."""

    def __init__(self, config: MenuConfig = None):
        self.config = config or MenuConfig()

        # State tracking
        self.root: Optional[tk.Tk] = None
        self.canvas: Optional[tk.Canvas] = None
        self.running = False
        self.visible = self.config.start_visible

        # Menu sections
        self._sections: dict = {}
        self._esp_state = True
        self._aimbot_state = True
        self._humanizer_state = True

    def create_window(self) -> None:
        """Create the external menu window with anti-detection measures."""
        self.root = tk.Tk()
        self.root.title(self.config.window_title)
        self.root.geometry(f"{self.config.window_size[0]}x{self.config.window_size[1]}+{self.config.window_position[0]}+{self.config.window_position[1]}")

        # Always on top for easy access during gameplay
        if self.config.always_on_top:
            self.root.attributes('-topmost', True)

        # Transparent background to reduce visual impact
        if self.config.transparent_background:
            self.root.configure(bg='#1a1a2e')
            self.root.wm_attributes('-transparentcolor', '#1a1a2e')

        # Create canvas for drawing
        self.canvas = tk.Canvas(
            self.root,
            bg='#1a1a2e',
            highlightthickness=0,
            bd=0
        )
        self.canvas.pack(fill=tk.BOTH, expand=True)

        # Draw initial content
        self._draw_initial_content()

        print(f"External menu created: {self.config.window_title}")

    def _draw_initial_content(self) -> None:
        """Draw the initial menu interface."""
        if not self.canvas:
            return

        # Title header
        self.canvas.create_text(
            350, 30,
            text="APEX CHEAT MENU",
            fill="#00ff7f",
            font=("Segoe UI", 20, "bold"),
            anchor="center"
        )

        # Status indicator
        self.canvas.create_text(
            50, 80,
            text="Status:",
            fill="#ffffff",
            font=("Segoe UI", 12),
            anchor="w"
        )
        self.status_text = self.canvas.create_text(
            120, 80,
            text="[RUNNING]",
            fill="#00ff7f",
            font=("Segoe UI", 12),
            anchor="w"
        )

        # ESP Section
        self.canvas.create_text(
            50, 130,
            text="ESP Overlay:",
            fill="#ffffff",
            font=("Segoe UI", 12),
            anchor="w"
        )
        self.esp_status = self.canvas.create_text(
            140, 130,
            text="[ENABLED]",
            fill="#00ff7f",
            font=("Segoe UI", 12),
            anchor="w"
        )

        # Aimbot Section
        self.canvas.create_text(
            50, 180,
            text="Aimbot:",
            fill="#ffffff",
            font=("Segoe UI", 12),
            anchor="w"
        )
        self.aimbot_status = self.canvas.create_text(
            120, 180,
            text="[ENABLED]",
            fill="#00ff7f",
            font=("Segoe UI", 12),
            anchor="w"
        )

        # Humanizer Section
        self.canvas.create_text(
            50, 230,
            text="Humanizer:",
            fill="#ffffff",
            font=("Segoe UI", 12),
            anchor="w"
        )
        self.humanizer_status = self.canvas.create_text(
            130, 230,
            text="[ENABLED]",
            fill="#00ff7f",
            font=("Segoe UI", 12),
            anchor="w"
        )

        # Key bindings display
        self.canvas.create_text(
            50, 300,
            text="Key Bindings:",
            fill="#ffffff",
            font=("Segoe UI", 12, "bold"),
            anchor="w"
        )

        # INSERT key hint
        self.canvas.create_text(
            50, 340,
            text="INSERT",
            fill="#00ff7f",
            font=("Segoe UI", 10),
            anchor="w"
        )
        self.canvas.create_text(
            120, 340,
            text="- Toggle menu visibility",
            fill="#aaaaaa",
            font=("Segoe UI", 10),
            anchor="w"
        )

        # HOME key hint
        self.canvas.create_text(
            50, 370,
            text="HOME",
            fill="#00ff7f",
            font=("Segoe UI", 10),
            anchor="w"
        )
        self.canvas.create_text(
            120, 370,
            text="- Toggle ESP overlay",
            fill="#aaaaaa",
            font=("Segoe UI", 10),
            anchor="w"
        )

        # Hotkey registration status
        self.canvas.create_text(
            50, 420,
            text="Hotkeys:",
            fill="#ffffff",
            font=("Segoe UI", 12, "bold"),
            anchor="w"
        )
        self.hotkey_status = self.canvas.create_text(
            120, 420,
            text="[REGISTERED]",
            fill="#00ff7f",
            font=("Segoe UI", 12),
            anchor="w"
        )

        # Draw decorative border
        self.canvas.create_rectangle(
            20, 20, 680, 480,
            outline="#00ff7f",
            width=2,
            tags="border"
        )

    def toggle_visibility(self) -> None:
        """Toggle menu visibility via INSERT key."""
        if not self.root:
            return

        self.visible = not self.visible

        if self.visible:
            self.root.deiconify()
            self.canvas.itemconfig(self.status_text, text="[VISIBLE]", fill="#00ff7f")
        else:
            self.root.withdraw()
            self.canvas.itemconfig(self.status_text, text="[HIDDEN]", fill="#ffa500")

        print(f"Menu {'shown' if self.visible else 'hidden'}")

    def toggle_esp(self) -> None:
        """Toggle ESP overlay from menu."""
        self._esp_state = not self._esp_state
        status = "[ENABLED]" if self._esp_state else "[DISABLED]"
        color = "#00ff7f" if self._esp_state else "#ffa500"

        if self.canvas and hasattr(self, 'esp_status'):
            self.canvas.itemconfig(self.esp_status, text=status, fill=color)

        print(f"ESP {'enabled' if self._esp_state else 'disabled'}")

    def toggle_aimbot(self) -> None:
        """Toggle aimbot from menu."""
        self._aimbot_state = not self._aimbot_state
        status = "[ENABLED]" if self._aimbot_state else "[DISABLED]"
        color = "#00ff7f" if self._aimbot_state else "#ffa500"

        if self.canvas and hasattr(self, 'aimbot_status'):
            self.canvas.itemconfig(self.aimbot_status, text=status, fill=color)

        print(f"Aimbot {'enabled' if self._aimbot_state else 'disabled'}")

    def toggle_humanizer(self) -> None:
        """Toggle humanizer from menu."""
        self._humanizer_state = not self._humanizer_state
        status = "[ENABLED]" if self._humanizer_state else "[DISABLED]"
        color = "#00ff7f" if self._humanizer_state else "#ffa500"

        if self.canvas and hasattr(self, 'humanizer_status'):
            self.canvas.itemconfig(self.humanizer_status, text=status, fill=color)

        print(f"Humanizer {'enabled' if self._humanizer_state else 'disabled'}")

    def update_player_count(self, count: int) -> None:
        """Update player count display."""
        if self.canvas:
            self.canvas.create_text(
                500, 80,
                text=f"Players: {count}",
                fill="#ffffff",
                font=("Segoe UI", 12),
                anchor="w",
                tags="player_count"
            )

    def start(self) -> None:
        """Start the external menu main loop."""
        if not self.root:
            self.create_window()

        # Show window before entering mainloop (per memory fix)
        if hasattr(self.root, 'deiconify'):
            self.root.deiconify()

        self.running = True
        print("External menu started - visible and ready!")

        try:
            while self.running:
                self.root.update_idletasks()
                self.root.update()
                time.sleep(0.05)  # 20 FPS for smooth UI
        except tk.TclError as e:
            print(f"Menu mainloop exited: {e}")
        finally:
            self.running = False

    def stop(self) -> None:
        """Stop the external menu."""
        self.running = False
        if self.root:
            try:
                self.root.quit()
            except tk.TclError:
                pass


def register_insert_hotkey(callback) -> int:
    """Register INSERT key as global hotkey for menu toggle."""
    hotkey_id = 100

    # Define callback for hotkey
    def hotkey_callback(wparam, lparam):
        if wparam == hotkey_id:
            callback()

    # Register hotkey with Windows API
    user32.RegisterHotKey.argtypes = [
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.c_uint,
        ctypes.c_uint
    ]

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
    """Main entry point for external menu."""
    config = MenuConfig(
        window_title="Apex Cheat Menu",
        window_size=(700, 500),
        window_position=(50, 50),
        start_visible=True,
        always_on_top=True,
        transparent_background=True,
        custom_window_class="ApexCheatMenu",
    )

    menu = ExternalMenu(config)

    # Register hotkeys
    register_insert_hotkey(menu.toggle_visibility)
    register_home_hotkey(menu.toggle_esp)

    # Start the menu
    menu.start()


if __name__ == "__main__":
    main()
