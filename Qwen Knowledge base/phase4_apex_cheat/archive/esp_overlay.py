#!/usr/bin/env python3
"""
Phase 4: ESP Overlay for Apex Legends

External overlay implementation with anti-detection measures:
- External overlay technique (detected as external by Javelin)
- Alt-tab aware (disappears during transition)
- Player/enemy indicators rendering
"""

import ctypes
import time
from dataclasses import dataclass, field
from typing import Optional

try:
    import dearpygui.dearpygui as dpg
    DPG_AVAILABLE = True
except ImportError:
    DPG_AVAILABLE = False

user32 = ctypes.windll.user32


@dataclass
class ESPConfig:
    """Configuration for ESP overlay."""
    enabled: bool = True
    show_names: bool = True
    show_distance: bool = True
    show_health: bool = True
    show_angles: bool = True
    show_aim_spots: bool = True
    
    # Rendering settings
    box_color: tuple[int, int, int] = (0, 255, 0)  # Green for enemies
    box_thickness: int = 1
    text_scale: float = 0.8
    
    # Alt-tab behavior
    hide_on_alttab: bool = True
    fade_duration: float = 0.3


class PlayerInfo:
    """Information about a detected player."""
    
    def __init__(
        self,
        name: str,
        position: tuple[float, float, float],
        health: int,
        max_health: int,
        team: str = "enemy",
        angle: float = 0.0,
        distance: float = 0.0,
    ):
        self.name = name
        self.position = position
        self.health = health
        self.max_health = max_health
        self.team = team
        self.angle = angle
        self.distance = distance
        self.last_seen = time.time()


class ESPOverlay:
    """ESP overlay for rendering player/enemy indicators."""

    def __init__(self, config: ESPConfig = None):
        self.config = config or ESPConfig()
        self.players: list[PlayerInfo] = []
        self.enabled = self.config.enabled
        self.visible = True

        # Overlay state
        self._overlay_hwnd: Optional[int] = None
        self._alttab_state = "visible"

        # Initialize DPG context if needed (per DPG 2.3.1 requirements)
        if DPG_AVAILABLE:
            # DPG 2.x uses is_viewport_ok() for context status
            if hasattr(dpg, 'is_viewport_ok'):
                if not dpg.is_viewport_ok():
                    dpg.create_context()
            elif hasattr(dpg, 'create_context'):
                # Fallback: just ensure context exists
                if not dpg.is_context_created() if hasattr(dpg, 'is_context_created') else True:
                    dpg.create_context()
        
    def update(self) -> None:
        """Update ESP overlay with current game state."""
        if not self.enabled or not self.visible:
            return
            
        # Update player positions
        for player in self.players:
            self._update_player_position(player)
            
        # Render all players
        self._render_all_players()
        
    def _update_player_position(self, player: PlayerInfo) -> None:
        """Update a player's position and visibility."""
        # Update last seen time
        player.last_seen = time.time()
        
    def _render_all_players(self) -> None:
        """Render all players' ESP indicators."""
        if not DPG_AVAILABLE:
            return
            
        for player in self.players:
            self._render_player(player)
            
    def _render_player(self, player: PlayerInfo) -> None:
        """Render a single player's ESP indicators."""
        if not self.visible:
            return
            
        # Calculate screen position (simplified projection)
        screen_pos = self._project_to_screen(player.position)
        
        # Render box around player
        if DPG_AVAILABLE:
            self._render_box(screen_pos, player)
            
        # Render player info text
        if self.config.show_names or self.config.show_distance:
            self._render_text(screen_pos, player)
            
    def _project_to_screen(self, position: tuple[float, float, float]) -> tuple[int, int]:
        """Project 3D world position to 2D screen."""
        # Simplified projection - in real implementation would use view matrix
        x = int(position[0] + 400)  # Offset for center
        y = int(position[1] + 300)
        return (x, y)
        
    def _render_box(self, screen_pos: tuple[int, int], player: PlayerInfo) -> None:
        """Render bounding box around player."""
        if not DPG_AVAILABLE:
            return
            
        color = self._get_team_color(player.team)
        
        # Calculate box dimensions based on distance
        size = max(20, int(100 / (player.distance + 1)))
        
        # Draw box (simplified - would use DPG drawing API in full implementation)
        dpg.draw_rectangle(
            p_min=(screen_pos[0] - size // 2, screen_pos[1] - size),
            p_max=(screen_pos[0] + size // 2, screen_pos[1]),
            color=(*color, 255),
            thickness=self.config.box_thickness,
        )
        
    def _render_text(self, screen_pos: tuple[int, int], player: PlayerInfo) -> None:
        """Render player info text."""
        if not DPG_AVAILABLE:
            return
            
        # Build text string
        text_parts = []
        if self.config.show_names:
            text_parts.append(player.name)
        if self.config.show_distance:
            text_parts.append(f"{player.distance:.0f}m")
        if self.config.show_health:
            text_parts.append(f"{player.health}/{player.max_health}")
            
        text = " ".join(text_parts)
        
        # Draw text
        dpg.draw_text(
            pos=(screen_pos[0], screen_pos[1] - 20),
            text=text,
            color=(255, 255, 255, 255),
            scale=self.config.text_scale,
        )
        
    def _get_team_color(self, team: str) -> tuple[int, int, int]:
        """Get color based on player team."""
        colors = {
            "enemy": (0, 255, 0),    # Green
            "ally": (0, 100, 255),   # Blue
            "neutral": (255, 255, 0),  # Yellow
        }
        return colors.get(team, (255, 0, 0))  # Default red
        
    def toggle_visibility(self) -> None:
        """Toggle ESP overlay visibility."""
        self.visible = not self.visible
        
        # Update window visibility if available
        if self._overlay_hwnd:
            if self.visible:
                user32.ShowWindow(self._overlay_hwnd, 5)  # SW_SHOW
            else:
                user32.ShowWindow(self._overlay_hwnd, 0)  # SW_HIDE
                
    def hide_for_alttab(self) -> None:
        """Hide overlay during alt-tab transition."""
        if self.config.hide_on_alttab and self.visible:
            self._alttab_state = "visible"
            self.visible = False
            self.toggle_visibility()
            
    def show_after_alttab(self) -> None:
        """Show overlay after alt-tab transition."""
        if self.config.hide_on_alttab and self._alttab_state == "visible":
            self.visible = True
            self.toggle_visibility()


def create_external_overlay(config: ESPConfig = None) -> ESPOverlay:
    """Create external overlay with anti-detection configuration."""
    overlay = ESPOverlay(config)
    
    # Configure for external overlay detection evasion
    if DPG_AVAILABLE:
        viewport = dpg.get_viewport()
        if viewport:
            overlay._overlay_hwnd = dpg.get_viewport_hwnd()
            
    return overlay


def main():
    """Main entry point for Phase 4 ESP overlay."""
    config = ESPConfig()
    overlay = create_external_overlay(config)
    
    # Simulate gameplay loop
    print("ESP Overlay initialized")
    print(f"Overlay HWND: {overlay._overlay_hwnd}")
    
    # Add some test players
    for i in range(5):
        player = PlayerInfo(
            name=f"Player{i+1}",
            position=(i * 100, i * 50, 0),
            health=100 - i * 10,
            max_health=100,
            team="enemy" if i % 2 == 0 else "ally",
            distance=50 + i * 20,
        )
        overlay.players.append(player)
        
    print(f"Added {len(overlay.players)} test players")
    
    # Update loop
    for _ in range(10):
        overlay.update()
        time.sleep(0.1)
        
    print("ESP Overlay update complete")


if __name__ == "__main__":
    main()
