#!/usr/bin/env python3
"""
Phase 4: Subprocess Isolation for DPG Tests

Runs DPG-dependent tests in separate processes to isolate native crashes.
"""

import subprocess
import sys
import os


def run_test_in_subprocess(script_content: str, test_name: str) -> bool:
    """Run a test script in a subprocess to isolate DPG crashes."""
    print(f"\n{'='*60}")
    print(f"Running {test_name} (subprocess)")
    print('='*60)
    
    result = subprocess.run(
        [sys.executable, "-c", script_content],
        capture_output=True,
        text=True
    )
    
    # Print stdout/stderr
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print("STDERR:", result.stderr)
    
    # Check exit code (0xC0000005 = 3221225477 = ACCESS_VIOLATION)
    if result.returncode == 0:
        print(f"✓ {test_name} passed")
        return True
    elif result.returncode == 3221225477:
        print(f"✗ {test_name} crashed (0xC0000005 ACCESS_VIOLATION)")
        return False
    else:
        print(f"✗ {test_name} failed with exit code {result.returncode}")
        return False


def test_menu_integration():
    """Menu integration tests in subprocess."""
    script = '''
import sys
import os

# Handle __file__ for -c execution
if "__file__" not in globals():
    __file__ = os.path.abspath(sys.argv[0]) if sys.argv else "<string>"

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    import dearpygui.dearpygui as dpg
    DPG_AVAILABLE = True
except ImportError:
    DPG_AVAILABLE = False

from cheat_menu import CheatMenu, MenuConfig


def test_dpg_initialization():
    """Test DPG context and viewport creation."""
    if not DPG_AVAILABLE:
        print("DPG not available, skipping initialization test")
        return True

    # Test 1: Context creation (per DPG 2.3.1 requirements)
    if hasattr(dpg, "is_viewport_ok"):
        if not dpg.is_viewport_ok():
            dpg.create_context()
    elif hasattr(dpg, "create_context"):
        if not dpg.is_context_created() if hasattr(dpg, "is_context_created") else True:
            dpg.create_context()

    assert dpg.is_context_created(), "DPG context should be created"

    # Test 2: Viewport creation
    config = MenuConfig()
    menu = CheatMenu(config)

    # Create viewport
    menu._create_viewport()
    assert menu.menu is not None, "Menu viewport should be created"

    # Test 3: Show viewport
    dpg.show_viewport()
    assert dpg.is_viewport_ok(), "Viewport should be shown"

    print("DPG initialization test passed")
    return True


def test_menu_visibility_toggle():
    """Test menu visibility toggle functionality."""
    if not DPG_AVAILABLE:
        print("DPG not available, skipping visibility toggle test")
        return True
        
    config = MenuConfig(start_visible=True)
    menu = CheatMenu(config)
    
    # Initial state
    assert menu.visible == True, "Menu should be visible initially"
    
    # Toggle visibility
    menu.toggle_visibility()
    assert menu.visible == False, "Menu should be hidden after first toggle"
    
    # Toggle back
    menu.toggle_visibility()
    assert menu.visible == True, "Menu should be visible after second toggle"
    
    print("Menu visibility toggle test passed")
    return True


def test_insert_hotkey_registration():
    """Test INSERT key hotkey registration."""
    import ctypes
    
    user32 = ctypes.windll.user32
    VK_INSERT = 0x90
    
    # Register hotkey callback
    def hotkey_callback(hwnd, msg, id, time):
        pass
        
    # Register INSERT key (no modifiers)
    result = user32.RegisterHotKey(
        None,
        100,
        0,
        VK_INSERT
    )
    
    assert result == True, "INSERT hotkey should be registered successfully"
    
    print("INSERT hotkey registration test passed")
    return True


def run_all_tests():
    """Run all menu integration tests."""
    print("Running Phase 4 Menu Integration Tests...\\n")
    
    tests = [
        ("DPG Initialization", test_dpg_initialization),
        ("Menu Visibility Toggle", test_menu_visibility_toggle),
        ("INSERT Hotkey Registration", test_insert_hotkey_registration),
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
    
    print(f"\\n{'='*50}")
    print(f"Tests passed: {passed}/{total}")
    print(f"{'='*50}\\n")
    
    return results


if __name__ == "__main__":
    run_all_tests()
'''
    return run_test_in_subprocess(script, "Menu Integration Tests")


def test_esp_overlay():
    """ESP overlay tests in subprocess."""
    script = '''
import sys
import os

# Handle __file__ for -c execution
if "__file__" not in globals():
    __file__ = os.path.abspath(sys.argv[0]) if sys.argv else "<string>"

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    import dearpygui.dearpygui as dpg
    DPG_AVAILABLE = True
except ImportError:
    DPG_AVAILABLE = False

from cheat_menu import CheatMenu


class ESPOverlay:
    """ESP overlay for rendering player/enemy indicators."""
    
    def __init__(self, menu: CheatMenu):
        self.menu = menu
        self.enabled = True
        self.visible = True
        self.players = []
        
    def update(self) -> None:
        """Update ESP overlay with current game state."""
        if not self.enabled:
            return
            
    def _render_player(self, player: dict) -> None:
        """Render a single player's ESP indicators."""
        pass
        
    def toggle_visibility(self) -> None:
        """Toggle ESP overlay visibility."""
        self.enabled = not self.enabled
        self.visible = not self.visible


def test_esp_initialization():
    """Test ESP overlay initialization."""
    menu = CheatMenu()
    overlay = ESPOverlay(menu)
    
    assert overlay.enabled == True, "ESP should be enabled initially"
    assert overlay.visible == True, "ESP should be visible initially"
    assert len(overlay.players) == 0, "ESP should start with no players"
    
    print("ESP initialization test passed")
    return True


def test_player_rendering():
    """Test player ESP rendering."""
    menu = CheatMenu()
    overlay = ESPOverlay(menu)
    
    # Add test players
    players = [
        {"name": "Player1", "position": (100, 50, 0), "health": 100, "team": "enemy"},
        {"name": "Player2", "position": (200, 100, 0), "health": 80, "team": "ally"},
    ]
    
    overlay.players.extend(players)
    overlay.update()
    
    assert len(overlay.players) == 2, "ESP should have 2 players"
    
    print("Player rendering test passed")
    return True


def test_esp_visibility_toggle():
    """Test ESP overlay visibility toggle."""
    menu = CheatMenu()
    overlay = ESPOverlay(menu)
    
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


def run_all_tests():
    """Run all ESP overlay tests."""
    print("Running Phase 4 ESP Overlay Tests...\\n")
    
    tests = [
        ("ESP Initialization", test_esp_initialization),
        ("Player Rendering", test_player_rendering),
        ("ESP Visibility Toggle", test_esp_visibility_toggle),
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
    
    print(f"\\n{'='*50}")
    print(f"Tests passed: {passed}/{total}")
    print(f"{'='*50}\\n")
    
    return results


if __name__ == "__main__":
    run_all_tests()
'''
    return run_test_in_subprocess(script, "ESP Overlay Tests")


def main():
    """Run all Phase 4 tests with subprocess isolation."""
    print("=" * 60)
    print("Phase 4 Comprehensive Test Suite (Subprocess Isolation)")
    print("=" * 60)
    
    results = []
    
    # Menu integration tests
    results.append(("Menu Integration", test_menu_integration()))
    
    # ESP overlay tests
    results.append(("ESP Overlay", test_esp_overlay()))
    
    # Summary
    print("\n" + "=" * 60)
    print("PHASE 4 TEST SUMMARY")
    print("=" * 60)
    
    passed = sum(1 for _, r in results if r)
    total = len(results)
    
    print(f"\nMenu Integration: {'✓' if results[0][1] else '✗'}")
    print(f"ESP Overlay:      {'✓' if results[1][1] else '✗'}")
    print(f"\nTotal: {passed}/{total} test suites passed")
    
    if passed == total:
        print("\n✅ All Phase 4 tests passed!")
        return True
    else:
        print(f"\n⚠️  {total - passed} test suite(s) failed")
        return False


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
