#!/usr/bin/env python3
"""Minimal DPG test to isolate crash."""

import sys

def test_import():
    """Test basic import."""
    print("Testing DPG import...")
    try:
        import dearpygui.dearpygui as dpg
        print(f"DPG version: {dpg.get_dearpygui_version()}")
        return dpg
    except Exception as e:
        print(f"Import error: {e}")
        return None

def test_context(dpg):
    """Test context creation."""
    print("Testing context creation...")
    try:
        dpg.create_context()
        print("Context created successfully")
        return True
    except Exception as e:
        print(f"Context error: {e}")
        return False

def test_viewport(dpg):
    """Test viewport creation - this is where crashes happen."""
    print("Testing viewport creation...")
    try:
        dpg.create_viewport(title="Test", width=800, height=600)
        print("Viewport created successfully")
        
        # Get viewport hwnd if available
        if hasattr(dpg, 'get_viewport_hwnd'):
            hwnd = dpg.get_viewport_hwnd()
            print(f"Viewport HWND: {hwnd}")
        
        return True
    except Exception as e:
        print(f"Viewport error: {e}")
        return False

def test_setup(dpg):
    """Test setup."""
    print("Testing setup...")
    try:
        dpg.setup_dearpygui()
        print("Setup completed")
        return True
    except Exception as e:
        print(f"Setup error: {e}")
        return False

def test_show(dpg):
    """Test showing viewport."""
    print("Testing show viewport...")
    try:
        dpg.show_viewport()
        print("Viewport shown successfully")
        return True
    except Exception as e:
        print(f"Show error: {e}")
        return False

def main():
    """Run all tests."""
    print("=" * 50)
    print("DPG Minimal Test Suite")
    print("=" * 50)

    dpg = test_import()
    if not dpg:
        print("FAILED at import")
        return 1

    if not test_context(dpg):
        print("FAILED at context")
        return 1

    if not test_viewport(dpg):
        print("FAILED at viewport - this is likely the crash point")
        return 1

    if not test_setup(dpg):
        print("FAILED at setup")
        return 1

    if not test_show(dpg):
        print("FAILED at show")
        return 1

    print("=" * 50)
    print("All tests passed!")
    print("=" * 50)
    return 0

if __name__ == "__main__":
    sys.exit(main())
