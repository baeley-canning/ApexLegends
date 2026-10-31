#!/usr/bin/env python3
"""
Phase 4: Menu Integration Tests

Tests for DPG menu initialization, visibility toggle, and alt-tab management.
"""

import sys
import os

# Add parent directory to path for imports
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
    # Check for is_viewport_ok() first (DPG 2.x), then is_context_created(), then fallback
    if hasattr(dpg, 'is_viewport_ok'):
        if not dpg.is_viewport_ok():
            dpg.create_context()
    elif hasattr(dpg, 'create_context'):
        if not dpg.is_context_created() if hasattr(dpg, 'is_context_created') else True:
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
    print("Running Phase 4 Menu Integration Tests...\n")
    
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
    
    print(f"\n{'='*50}")
    print(f"Tests passed: {passed}/{total}")
    print(f"{'='*50}\n")
    
    return results


if __name__ == "__main__":
    run_all_tests()
