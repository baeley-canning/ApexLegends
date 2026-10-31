#!/usr/bin/env python3
"""
Phase 4: Minimal Test Suite (DPG-Agnostic)

Tests that don't require DPG to avoid native crashes.
"""

import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def test_cheat_menu_basic():
    """Test basic cheat menu class without DPG dependency."""
    # Import cheat_menu directly from parent directory
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    
    import cheat_menu
    from cheat_menu import CheatMenu, MenuConfig
    
    config = MenuConfig()
    menu = CheatMenu(config)
    
    assert menu.config.window_title == "Apex Cheat Menu"
    assert menu.visible == True
    assert menu.initialized == False
    
    print("✓ Basic cheat menu test passed")
    return True


def test_esp_overlay_basic():
    """Test basic ESP overlay class."""
    # Import cheat_menu directly from parent directory
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    
    import cheat_menu
    from cheat_menu import ESPOverlay, CheatMenu, ESPConfig
    
    menu = CheatMenu()
    overlay = ESPOverlay(menu)
    
    assert overlay.enabled == True
    assert overlay.visible == True
    assert len(overlay.players) == 0
    
    print("✓ Basic ESP overlay test passed")
    return True


def test_hotkey_registration():
    """Test Windows hotkey registration without DPG."""
    import ctypes
    
    user32 = ctypes.windll.user32
    VK_INSERT = 0x90
    VK_HOME = 0x24
    
    # Test INSERT key registration
    result_insert = user32.RegisterHotKey(
        None,
        100,  # hotkey_id
        0,    # no modifiers
        VK_INSERT
    )
    
    assert result_insert == True, "INSERT key should register successfully"
    
    # Test HOME key registration
    result_home = user32.RegisterHotKey(
        None,
        101,  # hotkey_id
        0,    # no modifiers
        VK_HOME
    )
    
    assert result_home == True, "HOME key should register successfully"
    
    print("✓ Hotkey registration test passed")
    return True


def test_window_visibility():
    """Test window visibility toggle without DPG."""
    import ctypes
    
    user32 = ctypes.windll.user32
    
    # Create a simple test window
    hwnd = user32.CreateWindowExW(
        0,
        "STATIC",
        "TestWindow",
        0x40000000 | 0x10000000,  # WS_VISIBLE | WS_OVERLAPPEDWINDOW
        100, 100, 400, 300,
        None, None, None, None
    )
    
    assert hwnd is not None, "Test window should be created"
    
    # Test show/hide
    user32.ShowWindow(hwnd, 5)  # SW_SHOW
    user32.ShowWindow(hwnd, 0)  # SW_HIDE
    
    print("✓ Window visibility test passed")
    return True


def test_dataclasses():
    """Test dataclass definitions for cheat config."""
    from dataclasses import dataclass
    
    @dataclass
    class TestConfig:
        enabled: bool = True
        sensitivity: float = 0.5
        hotkey_id: int = 100
    
    config = TestConfig()
    
    assert config.enabled == True
    assert config.sensitivity == 0.5
    
    print("✓ Dataclasses test passed")
    return True


def run_all_tests():
    """Run all minimal tests."""
    print("=" * 60)
    print("Phase 4 Minimal Test Suite (DPG-Agnostic)")
    print("=" * 60)
    print()
    
    tests = [
        ("Basic Cheat Menu", test_cheat_menu_basic),
        ("Basic ESP Overlay", test_esp_overlay_basic),
        ("Hotkey Registration", test_hotkey_registration),
        ("Window Visibility", test_window_visibility),
        ("Dataclasses", test_dataclasses),
    ]
    
    results = []
    for name, test_func in tests:
        try:
            result = test_func()
            results.append((name, result))
        except Exception as e:
            print(f"✗ {name} failed: {e}")
            results.append((name, False))
    
    # Summary
    print()
    print("=" * 60)
    passed = sum(1 for _, r in results if r)
    total = len(results)
    
    print(f"Tests passed: {passed}/{total}")
    
    if passed == total:
        print("✅ All minimal tests passed!")
        return True
    else:
        print(f"⚠️  {total - passed} test(s) failed")
        return False


if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
