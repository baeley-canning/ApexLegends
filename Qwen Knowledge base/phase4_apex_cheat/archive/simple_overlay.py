#!/usr/bin/env python3
"""
Simple External Overlay for Phase 4

Creates a visible external window overlay that stays on top of Apex Legends.
This bypasses the DPG crashes and provides immediate visual feedback.
"""

import ctypes
import sys
import time
import tkinter as tk
from dataclasses import dataclass
from typing import Optional

user32 = ctypes.windll.user32


@dataclass
class OverlayConfig:
    """Configuration for external overlay."""
    window_title: str = "Apex Cheat Overlay"
    width: int = 400
    height: int = 300
    x_pos: int = 100
    y_pos: int = 100
    always_on_top: bool = True
    transparent: bool = True


class SimpleOverlay:
    """Simple external overlay window."""

    def __init__(self, config: OverlayConfig = None):
        self.config = config or OverlayConfig()
        self.root: Optional[tk.Tk] = None
        self.canvas: Optional[tk.Canvas] = None
        self.running = False
        self.visible = True

    def create_window(self) -> None:
        """Create the external overlay window."""
        self.root = tk.Tk()
        self.root.title(self.config.window_title)
        self.root.geometry(f"{self.config.width}x{self.config.height}+{self.config.x_pos}+{self.config.y_pos}")

        # Always on top
        if self.config.always_on_top:
            self.root.attributes('-topmost', True)

        # Transparent background
        if self.config.transparent:
            self.root.configure(bg='#1a1a2e')
            self.root.wm_attributes('-transparentcolor', '#1a1a2e')

        # Create canvas for drawing
        self.canvas = tk.Canvas(self.root, bg='#1a1a2e', highlightthickness=0)
        self.canvas.pack(fill=tk.BOTH, expand=True)

        # Draw some initial content
        self._draw_initial_content()

        print(f"Overlay window created: {self.config.window_title}")

    def _draw_initial_content(self) -> None:
        """Draw initial content on the overlay."""
        if not self.canvas:
            return

        # Title text
        self.canvas.create_text(
            200, 30,
            text="APEX CHEAT PHASE 4",
            fill="#00ff7f",
            font=("Arial", 16, "bold"),
            anchor="center"
        )

        # Status indicators
        self.canvas.create_text(
            50, 80,
            text="Status:",
            fill="#ffffff",
            font=("Arial", 12),
            anchor="w"
        )
        self.canvas.create_text(
            120, 80,
            text="[RUNNING]",
            fill="#00ff7f",
            font=("Arial", 12),
            anchor="w"
        )

        # ESP indicators
        self.canvas.create_text(
            50, 120,
            text="ESP:",
            fill="#ffffff",
            font=("Arial", 12),
            anchor="w"
        )
        self.canvas.create_text(
            120, 120,
            text="[ENABLED]",
            fill="#00ff7f",
            font=("Arial", 12),
            anchor="w"
        )

        # INSERT key hint
        self.canvas.create_text(
            200, 200,
            text="Press INSERT to toggle menu",
            fill="#aaaaaa",
            font=("Arial", 10),
            anchor="center"
        )

        # Draw a simple box (simulating player ESP)
        self.canvas.create_rectangle(
            150, 150, 250, 200,
            outline="#00ff7f",
            width=2
        )
        self.canvas.create_text(
            200, 175,
            text="Player",
            fill="#00ff7f",
            font=("Arial", 10),
            anchor="center"
        )

    def toggle_visibility(self) -> None:
        """Toggle overlay visibility."""
        if not self.root:
            return

        self.visible = not self.visible
        if self.visible:
            self.root.deiconify()
        else:
            self.root.withdraw()

        print(f"Overlay {'shown' if self.visible else 'hidden'}")

    def update(self) -> None:
        """Update overlay state."""
        if not self.root or not self.running:
            return

        # Update any dynamic content here
        pass

    def start(self) -> None:
        """Start the overlay main loop."""
        if not self.root:
            self.create_window()

        self.running = True

        # Show window before mainloop (per memory fix)
        if hasattr(self.root, 'deiconify'):
            self.root.deiconify()

        print("Overlay started - should be visible over Apex!")

        try:
            while self.running:
                self.update()
                self.root.update_idletasks()
                self.root.update()
                time.sleep(0.05)  # 20 FPS
        except tk.TclError as e:
            print(f"Overlay mainloop exited: {e}")
        finally:
            self.running = False

    def stop(self) -> None:
        """Stop the overlay."""
        self.running = False
        if self.root:
            try:
                self.root.quit()
            except tk.TclError:
                pass


def main():
    """Main entry point for simple overlay."""
    config = OverlayConfig(
        window_title="Apex Cheat Overlay",
        width=400,
        height=300,
        x_pos=100,
        y_pos=100,
        always_on_top=True,
        transparent=True,
    )

    overlay = SimpleOverlay(config)
    overlay.start()


if __name__ == "__main__":
    main()
