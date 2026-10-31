#!/usr/bin/env python3
"""Verify cheat is actually being presented on top of Apex."""

import win32gui
import win32con
import ctypes

def get_all_windows():
    """Get all visible windows with their details."""
    windows = []
    
    def enum_callback(hwnd, results):
        if win32gui.IsWindowVisible(hwnd):
            title = win32gui.GetWindowText(hwnd)
            cls = win32gui.GetClassName(hwnd)
            rect = win32gui.GetWindowRect(hwnd)
            style = win32gui.GetWindowLong(hwnd, win32con.GWL_STYLE)
            ex_style = win32gui.GetWindowLong(hwnd, win32con.GWL_EXSTYLE)
            
            # Check if on top
            z_order = win32gui.GetWindow(hwnd, 3)  # GW_HWNDNEXT = 3, used for Z-order
            is_always_on_top = (ex_style & win32con.WS_EX_TOPMOST) != 0
            
            results.append({
                'hwnd': hex(hwnd),
                'title': title,
                'class': cls,
                'position': (rect[0], rect[1]),
                'size': (rect[2] - rect[0], rect[3] - rect[1]),
                'z_order': z_order,
                'always_on_top': is_always_on_top,
            })
    
    win32gui.EnumWindows(enum_callback, windows)
    return sorted(windows, key=lambda w: w['z_order'])

def check_apex_windows():
    """Check for Apex and cheat-related windows."""
    windows = get_all_windows()
    
    print("=" * 80)
    print("CURRENT WINDOWS (sorted by Z-order, topmost last)")
    print("=" * 80)
    
    apex_windows = []
    cheat_windows = []
    
    for w in windows:
        title_lower = w['title'].lower()
        cls_lower = w['class'].lower()
        
        is_apex = 'apex' in title_lower or 'r5apex' in title_lower
        is_cheat = any(x in cls_lower for x in ['dear', 'dpg', 'imgui', 'tk', 'cheat', 'menu'])
        is_overlay = 'overlay' in cls_lower or 'overlay' in title_lower
        
        if is_apex or is_cheat or is_overlay:
            apex_windows.append(w)
            if is_cheat or is_overlay:
                cheat_windows.append(w)
    
    # Print all windows with markers
    for w in windows:
        markers = []
        if any(aw['hwnd'] == w['hwnd'] for aw in apex_windows):
            markers.append('[APEX]')
        if any(cw['hwnd'] == w['hwnd'] for cw in cheat_windows):
            markers.append('[CHEAT]')
        if w['always_on_top']:
            markers.append('[TOPMOST]')
        
        marker_str = ' '.join(markers)
        print(f"{w['hwnd']} | {w['class']:35} | {w['title'][:40]:40} | {marker_str}")
    
    print("\n" + "=" * 80)
    print("CHEAT WINDOWS FOUND")
    print("=" * 80)
    
    if cheat_windows:
        for w in cheat_windows:
            print(f"\nWindow: {w['title']}")
            print(f"  Class:     {w['class']}")
            print(f"  Position:  {w['position']}")
            print(f"  Size:      {w['size']}")
            print(f"  Topmost:   {w['always_on_top']}")
    else:
        print("\n[NO CHEAT WINDOWS FOUND]")
    
    return cheat_windows

def check_directx_overlays():
    """Check for DirectX/overlay rendering."""
    print("\n" + "=" * 80)
    print("DIRECTX OVERLAY CHECK")
    print("=" * 80)
    
    try:
        # Check for D3D12 device creation
        from ctypes import windll
        d3d12 = windll.d3d12
        print("[D3D12] Library loaded successfully")
    except Exception as e:
        print(f"[D3D12] Not available: {e}")
    
    try:
        dxgi = windll.dxgi
        print("[DXGI] Library loaded successfully")
    except Exception as e:
        print(f"[DXGI] Not available: {e}")

def verify_shared_memory():
    """Verify shared memory connection."""
    print("\n" + "=" * 80)
    print("SHARED MEMORY VERIFICATION")
    print("=" * 80)
    
    try:
        import ctypes
        from ctypes import wintypes
        
        # Try to open shared memory
        hMapFile = ctypes.windll.kernel32.OpenFileMappingW(
            0x1F,  # FILE_MAP_ALL_ACCESS
            False,
            'Global\\ApexCheatMenuData'
        )
        
        if hMapFile:
            print("[OK] Shared memory mapping opened")
            
            # Map view
            pMem = ctypes.windll.kernel32.MapViewOfFile(
                hMapFile,
                0x1F,
                0, 0,
                4096
            )
            
            if pMem:
                print("[OK] Shared memory mapped")
                
                # Read test data
                buffer = (ctypes.c_uint32 * 16)()
                ctypes.memmove(buffer, pMem, ctypes.sizeof(buffer))
                
                print(f"[DATA] First 16 DWORDs: {list(buffer[:8])}")
                
                ctypes.windll.kernel32.UnmapViewOfFile(pMem)
            ctypes.windll.kernel32.CloseHandle(hMapFile)
            
            return True
        else:
            print("[FAIL] Could not open shared memory")
            return False
            
    except Exception as e:
        print(f"[ERROR] Shared memory check failed: {e}")
        return False

def main():
    """Run all verification checks."""
    print("\n" + "=" * 80)
    print("   PHASE 4 CHEAT VISIBILITY VERIFICATION")
    print("=" * 80)
    
    # Check current state
    cheat_windows = check_apex_windows()
    check_directx_overlays()
    verify_shared_memory()
    
    # Summary
    print("\n" + "=" * 80)
    print("VERIFICATION SUMMARY")
    print("=" * 80)
    
    if cheat_windows:
        print(f"\n[OK] Found {len(cheat_windows)} cheat-related window(s)")
        for w in cheat_windows:
            print(f"  - {w['title']} ({w['class']})")
    else:
        print("\n[NO CHEAT WINDOWS] Menu may be rendering via DirectX overlay instead")
    
    print("\n[NOTE] If no windows found, cheat may be using:")
    print("  1. DirectX overlay (D3D11/D3D12) rendering directly to Apex buffers")
    print("  2. Internal ImGui overlay (Kernaim/Ignite pattern)")
    print("  3. Shared memory IPC for menu state synchronization")
    
    return len(cheat_windows) > 0

if __name__ == "__main__":
    success = main()
    input("\nPress ENTER to exit...")
