#!/usr/bin/env python3
"""
Subprocess Launcher for Phase 4 DPG Menu

Isolates DPG menu in a separate process to avoid native library conflicts
that cause ACCESS_VIOLATION (0xC0000005) during create_viewport().
"""

import ctypes
import multiprocessing as mp
import signal
import sys
import time
from dataclasses import dataclass
from typing import Optional

try:
    import dearpygui.dearpygui as dpg
    DPG_AVAILABLE = True
except ImportError:
    DPG_AVAILABLE = False


@dataclass
class MenuConfig:
    """Configuration for the cheat menu."""
    window_title: str = "Apex Cheat Menu"
    window_size: tuple[int, int] = (800, 600)
    window_position: tuple[int, int] = (100, 100)
    start_visible: bool = True


class DPGMenuProcess:
    """DPG menu running in isolated subprocess."""

    def __init__(self, config: MenuConfig = None):
        self.config = config or MenuConfig()
        self.running = False
        self.visible = self.config.start_visible

    def run(self) -> int:
        """Run the DPG menu in subprocess."""
        print(f"[DPG Menu PID {mp.current_process().pid}] Starting DPG menu...")

        # Initialize DPG context (per DPG 2.3.1 requirements)
        if DPG_AVAILABLE:
            if hasattr(dpg, 'is_viewport_ok'):
                if not dpg.is_viewport_ok():
                    dpg.create_context()
            elif hasattr(dpg, 'create_context'):
                if not dpg.is_context_created() if hasattr(dpg, 'is_context_created') else True:
                    dpg.create_context()

        try:
            # Create viewport
            print(f"[DPG Menu PID {mp.current_process().pid}] Creating viewport...")
            dpg.create_viewport(
                title=self.config.window_title,
                width=self.config.window_size[0],
                height=self.config.window_size[1],
                x_pos=self.config.window_position[0],
                y_pos=self.config.window_position[1],
            )

            # Setup Dear PyGui
            print(f"[DPG Menu PID {mp.current_process().pid}] Setting up Dear PyGui...")
            dpg.setup_dearpygui()

            # Show viewport
            print(f"[DPG Menu PID {mp.current_process().pid}] Showing viewport...")
            dpg.show_viewport()

            self.running = True

            # Main loop
            while self.running:
                dpg.render_dearpygui_frame()

                # Simulate menu interactions
                if self.visible:
                    time.sleep(0.05)  # 20 Hz render rate
                else:
                    time.sleep(0.1)

        except Exception as e:
            print(f"[DPG Menu PID {mp.current_process().pid}] Error: {e}")
            return 1

        finally:
            # Cleanup
            if DPG_AVAILABLE:
                dpg.destroy_context()

        print(f"[DPG Menu PID {mp.current_process().pid}] Stopped successfully")
        return 0


def run_dpg_menu_in_subprocess(config: MenuConfig = None) -> int:
    """Run DPG menu in isolated subprocess."""
    process = DPGMenuProcess(config)

    # Use spawn method for clean isolation
    ctx = mp.get_context('spawn')
    p = ctx.Process(target=_subprocess_target, args=(config,))
    p.start()
    p.join()

    return p.exitcode


def _subprocess_target(config: MenuConfig) -> None:
    """Subprocess entry point."""
    process = DPGMenuProcess(config)
    exit_code = process.run()
    sys.exit(exit_code)


def main() -> int:
    """Main entry point for subprocess launcher."""
    config = MenuConfig(
        window_title="Apex Cheat Menu",
        window_size=(800, 600),
        window_position=(100, 100),
        start_visible=True,
    )

    print("Starting Phase 4 DPG Menu with subprocess isolation...")
    exit_code = run_dpg_menu_in_subprocess(config)

    if exit_code == 0:
        print("DPG Menu completed successfully")
    else:
        print(f"DPG Menu exited with code {exit_code}")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
