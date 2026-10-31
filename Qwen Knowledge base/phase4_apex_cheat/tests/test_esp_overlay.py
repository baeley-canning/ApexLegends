#!/usr/bin/env python3
"""
Phase 4: ESP Overlay Tests

Tests for ESP overlay rendering, player indicators, and alt-tab management.
"""

import sys
import os
import time

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    import dearpygui.dearpygui as dpg
    DPG_AVAILABLE = True
except ImportError:
    DPG_AVAILABLE = False

from esp_overlay import ESPOverlay, ESPConfig, PlayerInfo, create_external_overlay


def test_esp_initialization():
    """Test ESP overlay initialization."""
    config = ESPConfig()
    overlay = ESPOverlay(config)
    
    assert overlay.enabled == True, "ESP should be enabled initially"
    assert overlay.visible == True, "ESP should be visible initially"
    assert len(overlay.players) == 0, "ESP should start with no players"
    
    print("ESP initialization test passed")
    return True


def test_player_rendering():
    """Test player ESP rendering."""
    config = ESPConfig(
        show_names=True,
        show_distance=True,
        show_health=True,
    )
    overlay = ESPOverlay(config)
    
    # Add test players
    players = [
        PlayerInfo(
            name="Player1",
            position=(100, 50, 0),
            health=100,
            max_health=100,
            team="enemy",
            distance=50,
        ),
        PlayerInfo(
            name="Player2",
            position=(200, 100, 0),
            health=80,
            max_health=100,
            team="ally",
            distance=75,
        ),
    ]
    
    overlay.players.extend(players)
    
    # Update ESP
    overlay.update()
    
    assert len(overlay.players) == 2, "ESP should have 2 players"
    
    print("Player rendering test passed")
    return True


def test_esp_visibility_toggle():
    """Test ESP overlay visibility toggle."""
    config = ESPConfig()
    overlay = ESPOverlay(config)
    
    # Initial state
    assert overlay.visible == True, "ESP should be visible initially"
    
    # Toggle off
    overlay.toggle_visibility()
    assert overlay.visible == False, "ESP should be hidden after first toggle"
    
    # Toggle back on
    overlay.toggle_visibility()
    assert overlay.visible == True, "ESP should be visible after second toggle"
    
    print("ESP visibility toggle test passed")
    return True


def test_alttab_management():
    """Test alt-tab window state management."""
    config = ESPConfig(hide_on_alttab=True)
    overlay = ESPOverlay(config)
    
    # Initial state
    assert overlay._alttab_state == "visible", "Alt-tab state should be visible initially"
    
    # Hide for alt-tab
    overlay.hide_for_alttab()
    assert overlay.visible == False, "ESP should hide during alt-tab"
    
    # Show after alt-tab
    overlay.show_after_alttab()
    assert overlay.visible == True, "ESP should show after alt-tab"
    
    print("Alt-tab management test passed")
    return True


def test_project_to_screen():
    """Test 3D to 2D screen projection."""
    config = ESPConfig()
    overlay = ESPOverlay(config)
    
    # Test projection
    position = (100, 50, 0)
    screen_pos = overlay._project_to_screen(position)
    
    assert isinstance(screen_pos, tuple), "Screen position should be a tuple"
    assert len(screen_pos) == 2, "Screen position should have x and y coordinates"
    
    print("Project to screen test passed")
    return True


def run_all_tests():
    """Run all ESP overlay tests."""
    print("Running Phase 4 ESP Overlay Tests...\n")
    
    tests = [
        ("ESP Initialization", test_esp_initialization),
        ("Player Rendering", test_player_rendering),
        ("ESP Visibility Toggle", test_esp_visibility_toggle),
        ("Alt-tab Management", test_alttab_management),
        ("Project to Screen", test_project_to_screen),
    ]
    
    results = []
    for name, test_func in tests:
        try:
            result = test_func()
            results.append((name, result))
        except Exception as e:
            print(f"{name} failed: {e}")
            results.append((name, False))
            
    # Summary
    passed = sum(1 for _, r in results if r)
    total = len(results)
    
    print(f"\n{'='*50}")
    print(f"Tests passed: {passed}/{total}")
    print(f"{'='*50}\n")
    
    return results


if __name__ == "__main__":
    run_all_tests()
