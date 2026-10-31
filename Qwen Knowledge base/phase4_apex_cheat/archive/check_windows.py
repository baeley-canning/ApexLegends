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


# EnumWindows(lpEnumFunc, lParam) - correct order for WinAPI
user32.EnumWindows(enum_window, None)

print('All windows:')
for w in windows:
    status = []
    if w['visible']:
        status.append('VISIBLE')
    if w['enabled']:
        status.append('ENABLED')
    status_str = f' [{",".join(status)}]' if status else ''
    print(f'  {status_str} [{w["class"]}] {w["title"]}')

print()
print('Visible windows (filtered):')
for w in windows:
    if w['visible'] and ('Apex' in w['title'] or 'DPG' in w['title'] or 'Dear' in w['title'] or 'Cheat' in w['title'] or 'Menu' in w['title']):
        print(f'  [{w["class"]}] {w["title"]}')
