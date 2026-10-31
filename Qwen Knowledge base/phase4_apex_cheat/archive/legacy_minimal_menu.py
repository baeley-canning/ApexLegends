#!/usr/bin/env python3
"""
Minimalist External Menu for Apex Cheat

Clean, uncluttered overlay - no bloat, just essential info.
Designed for low visual impact and easy positioning.
"""

import ctypes
import threading
import time
import tkinter as tk
from dataclasses import dataclass
from typing import Optional

user32 = ctypes.windll.user32


@dataclass
class MenuConfig:
    window_title: str = "Apex Menu"
    size: tuple[int, int] = (280, 180)
    pos: tuple[int, int] = (100, 100)
    start_visible: bool = True
    always_on_top: bool = True


class MinimalMenu:
    """Minimalist menu - clean and uncluttered."""

    def __init__(self, config: MenuConfig = None):
        self.config = config or MenuConfig()
        self.root: Optional[tk.Tk] = None
        self.canvas: Optional[tk.Canvas] = None
        self.running = False
        self.visible = True

    def create_window(self) -> None:
        """Create minimal menu window."""
        self.root = tk.Tk()
        self.root.title(self.config.window_title)
        self.root.geometry(f"{self.config.size[0]}x{self.config.size[1]}+{self.config.pos[0]}+{self.config.pos[1]}")

        if self.config.always_on_top:
            self.root.attributes('-topmost', True)

        # Clean dark theme
        self.root.configure(bg='#1a1a1a')
        self.root.wm_attributes('-transparentcolor', '#1a1a1a')

        self.canvas = tk.Canvas(
            self.root,
            bg='#1a1a1a',
            highlightthickness=0,
            bd=0
        )
        self.canvas.pack(fill=tk.BOTH, expand=True)

        # Draw minimal content
        self._draw()

    def _draw(self) -> None:
        """Draw clean minimal interface."""
        c = self.canvas

        # Status indicator (top)
        c.create_text(
            140, 25,
            text="APEX MENU",
            fill="#00ff7f",
            font=("Segoe UI", 16, "bold"),
            anchor="center"
        )

        # ESP toggle
        c.create_text(50, 60, text="ESP:", fill="#fff", font=("Segoe UI", 11), anchor="w")
        self.esp_txt = c.create_text(90, 60, text="[ON]", fill="#00ff7f", font=("Segoe UI", 11), anchor="w")

        # Aimbot toggle
        c.create_text(50, 85, text="Aim:", fill="#fff", font=("Segoe UI", 11), anchor="w")
        self.aim_txt = c.create_text(90, 85, text="[ON]", fill="#00ff7f", font=("Segoe UI", 11), anchor="w")

        # Humanizer toggle
        c.create_text(50, 110, text="Human:", fill="#fff", font=("Segoe UI", 11), anchor="w")
        self.human_txt = c.create_text(100, 110, text="[ON]", fill="#00ff7f", font=("Segoe UI", 11), anchor="w")

        # Key hints (bottom)
        c.create_text(60, 145, text="INSERT: Menu", fill="#888", font=("Segoe UI", 9), anchor="w")
        c.create_text(180, 145, text="HOME: ESP", fill="#888", font=("Segoe UI", 9), anchor="w")

    def toggle_visibility(self) -> None:
        """Toggle menu visibility."""
        if not self.root:
            return
        self.visible = not self.visible
        if self.visible:
            self.root.deiconify()
        else:
            self.root.withdraw()

    def toggle_esp(self) -> None:
        """Toggle ESP on/off."""
        self.esp_state = not getattr(self, 'esp_state', True)
        color = "#00ff7f" if self.esp_state else "#ffa500"
        text = "[ON]" if self.esp_state else "[OFF]"
        if self.canvas and hasattr(self, 'esp_txt'):
            self.canvas.itemconfig(self.esp_txt, text=text, fill=color)

    def toggle_aimbot(self) -> None:
        """Toggle aimbot on/off."""
        self.aim_state = not getattr(self, 'aim_state', True)
        color = "#00ff7f" if self.aim_state else "#ffa500"
        text = "[ON]" if self.aim_state else "[OFF]"
        if self.canvas and hasattr(self, 'aim_txt'):
            self.canvas.itemconfig(self.aim_txt, text=text, fill=color)

    def toggle_humanizer(self) -> None:
        """Toggle humanizer on/off."""
        self.human_state = not getattr(self, 'human_state', True)
        color = "#00ff7f" if self.human_state else "#ffa500"
        text = "[ON]" if self.human_state else "[OFF]"
        if self.canvas and hasattr(self, 'human_txt'):
            self.canvas.itemconfig(self.human_txt, text=text, fill=color)

    def start(self) -> None:
        """Start menu."""
        if not self.root:
            self.create_window()

        if hasattr(self.root, 'deiconify'):
            self.root.deiconify()

        self.running = True
        print("Minimal menu started - clean and simple!")

        try:
            while self.running:
                self.root.update_idletasks()
                self.root.update()
                time.sleep(0.05)
        except tk.TclError:
            pass
        finally:
            self.running = False

    def stop(self) -> None:
        """Stop menu."""
        self.running = False
        if self.root:
            try:
                self.root.quit()
            except tk.TclError:
                pass


def register_hotkey(vk: int, callback, hotkey_id: int = 100) -> None:
    """Register a global hotkey."""
    user32.RegisterHotKey.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_uint, ctypes.c_uint]

    result = user32.RegisterHotKey(None, hotkey_id, 0, vk)
    if result:
        print(f"Hotkey registered (ID: {hotkey_id})")


def main():
    """Main entry."""
    config = MenuConfig(
        window_title="Apex Menu",
        size=(280, 180),
        pos=(100, 100),
        start_visible=True,
        always_on_top=True,
    )

    menu = MinimalMenu(config)

    # Register hotkeys
    register_hotkey(0x90, menu.toggle_visibility, 100)  # INSERT
    register_hotkey(0x24, menu.toggle_esp, 101)        # HOME

    menu.start()


if __name__ == "__main__":
    main()
