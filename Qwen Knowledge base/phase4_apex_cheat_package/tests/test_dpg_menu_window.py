#!/usr/bin/env python3
"""
Test DPG menu window visibility in window enumeration.

Verifies the DPG menu appears with:
- Title: "Apex Cheat Menu"
- Class: "DearPyGui"
"""

import ctypes

user32 = ctypes.windll.user32
windows = []

# Setup EnumWindows with correct argtypes
user32.EnumWindows.argtypes = [ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p), ctypes.c_void_p]
user32.EnumWindows.restype = ctypes.c_bool

EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)


@EnumWindowsProc
def enum_window(hwnd, lParam):
    # Get window text
    buf = ctypes.create_unicode_buffer(100)
    user32.GetWindowTextW(hwnd, buf, 100)

    # Get class name
    class_buf = ctypes.create_unicode_buffer(50)
    user32.GetClassNameW(hwnd, class_buf, 50)

    # Check visibility
    is_visible = user32.IsWindowVisible(hwnd)
    is_enabled = user32.IsWindowEnabled(hwnd)

    windows.append({
        'hwnd': hwnd,
        'title': buf.value,
        'class': class_buf.value,
        'visible': is_visible,
        'enabled': is_enabled,
    })
    return True


def find_dpg_menu():
    """Find DPG menu window in enumeration."""
    # Enumerate all windows
    user32.EnumWindows(enum_window, None)

    # Filter for DPG menu
    dpg_windows = [
        w for w in windows
        if 'Dear' in w['class'] or 'DearPyGui' in w['title']
    ]

    return dpg_windows


def main():
    """Test DPG menu window enumeration."""
    print("DPG Menu Window Enumeration Test")
    print("=" * 60)

    # Enumerate windows
    dpg_windows = find_dpg_menu()

    if not dpg_windows:
        print("\nNo DPG menu windows found.")
        print("Make sure the DPG menu subprocess is running:")
        print("  python dpg_menu_subprocess.py")
        return

    print(f"\nFound {len(dpg_windows)} DPG window(s):")
    for w in dpg_windows:
        status = []
        if w['visible']:
            status.append('VISIBLE')
        if w['enabled']:
            status.append('ENABLED')
        status_str = f' [{",".join(status)}]' if status else ''

        print(f"\n  Window:{status_str}")
        print(f"    Title:  {w['title']}")
        print(f"    Class:  {w['class']}")
        print(f"    Hwnd:   0x{int(w['hwnd']):X}")

    # Check for specific "Apex Cheat Menu"
    apex_menu = [
        w for w in dpg_windows
        if 'Apex Cheat Menu' in w['title']
    ]

    print("\n" + "=" * 60)
    if apex_menu:
        print("SUCCESS: Apex Cheat Menu found!")
        for w in apex_menu:
            print(f"  - Title: {w['title']}")
            print(f"    Class: {w['class']}")
            print(f"    Visible: {w['visible']}")
    else:
        print("INFO: No 'Apex Cheat Menu' window found.")
        print("  (May appear after INSERT key press or DPG subprocess start)")

    return apex_menu


if __name__ == "__main__":
    main()
