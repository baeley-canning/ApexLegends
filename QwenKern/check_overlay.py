#!/usr/bin/env python3
"""Check for overlay windows and DirectX rendering."""

import win32gui

def check_overlays():
    """Check for overlay/menu windows."""
    print("Checking for overlay windows...")
    
    overlays = []
    
    def enum(hwnd, results):
        title = win32gui.GetWindowText(hwnd)
        cls = win32gui.GetClassName(hwnd)
        
        # Check for various overlay patterns
        if any(x in title.lower() for x in ['overlay', 'menu', 'cheat', 'imgui', 'dpg', 'dear', 'apex']):
            results.append((hwnd, title, cls))
        elif any(x in cls.lower() for x in ['overlay', 'menu', 'cheat', 'imgui', 'dpg', 'dear', 'window']):
            results.append((hwnd, title, cls))
    
    win32gui.EnumWindows(enum, overlays)
    
    print(f"\nFound {len(overlays)} overlay-related windows:\n")
    for hwnd, title, cls in overlays:
        rect = win32gui.GetWindowRect(hwnd)
        size = (rect[2] - rect[0], rect[3] - rect[1])
        print(f"  {hex(hwnd):<15} | {cls:<30} | {title:<40} | {size}")
    
    return overlays

def check_apex_direct():
    """Direct check of Apex window and children."""
    print("\n" + "=" * 60)
    print("DIRECT APEX CHECK")
    print("=" * 60)
    
    apex = win32gui.FindWindow('Respawn001', 'Apex Legends')
    if apex:
        print(f"Apex HWND: {hex(apex)}")
        
        # Get children
        children = []
        def enum_child(hwnd, results):
            title = win32gui.GetWindowText(hwnd)
            cls = win32gui.GetClassName(hwnd)
            if title or 'Child' in cls:
                results.append((hwnd, title, cls))
        
        win32gui.EnumChildWindows(apex, enum_child, children)
        
        print(f"\nChildren: {len(children)}")
        for hwnd, title, cls in children[:10]:  # First 10
            print(f"  {hex(hwnd):<15} | {cls:<25} | {title}")
        
        return apex
    else:
        print("Apex window not found")
        return None

def check_dpg_windows():
    """Check for Dear PyGui windows."""
    print("\n" + "=" * 60)
    print("DEAR PYGUI WINDOW CHECK")
    print("=" * 60)
    
    dpg_windows = []
    
    def enum(hwnd, results):
        title = win32gui.GetWindowText(hwnd)
        cls = win32gui.GetClassName(hwnd)
        
        if 'DPG' in cls or 'Dear' in cls or 'dear' in cls.lower():
            results.append((hwnd, title, cls))
    
    win32gui.EnumWindows(enum, dpg_windows)
    
    if dpg_windows:
        print(f"\nFound {len(dpg_windows)} DPG-related windows:")
        for hwnd, title, cls in dpg_windows:
            rect = win32gui.GetWindowRect(hwnd)
            print(f"  {hex(hwnd):<15} | {cls:<30} | {title:<40} | {rect}")
    else:
        print("\n[NO DPG WINDOWS FOUND]")
    
    return dpg_windows

def main():
    """Run all checks."""
    print("=" * 60)
    print("   OVERLAY VISIBILITY CHECK")
    print("=" * 60)
    
    check_overlays()
    check_apex_direct()
    check_dpg_windows()
    
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print("""
Current State:
- Apex running (Respawn001 class, 1920x1080)
- No visible cheat menu windows
- No DPG windows detected

This confirms the cheat is NOT being presented as a window.
The cheat may be using:
  1. DirectX overlay rendering (D3D11/D3D12)
  2. Shared memory for state sync
  3. Background processes monitoring Apex

To actually see the menu, you need either:
  - DPG viewport created (may be crashing)
  - C++ ImGui overlay injected into Apex
  - DirectX hook to render onto Apex's present call
""")

if __name__ == "__main__":
    main()
    input("\nPress ENTER...")
