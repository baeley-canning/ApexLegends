"""Why can't we open r5apex_dx12.exe?  Probe handle rights + elevation state."""
import ctypes
import ctypes.wintypes as wt
import struct
import subprocess

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
ntdll = ctypes.WinDLL("ntdll")

PID = 11996

MASKS = {
    "QUERY_LIMITED_INFORMATION": 0x1000,
    "VM_READ": 0x0010,
    "VM_READ|QUERY_LIMITED": 0x1010,
    "QUERY_INFORMATION": 0x0400,
    "VM_READ|QUERY_INFORMATION": 0x0410,
    "VM_READ|VM_WRITE|VM_OPERATION": 0x0038,
    "PROCESS_ALL_ACCESS": 0x1F0FFF,
}

print("elevated:", subprocess.run(
    ["powershell", "-NoProfile", "-Command",
     "([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())"
     ".IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"],
    capture_output=True, text=True).stdout.strip())

for name, mask in MASKS.items():
    ctypes.set_last_error(0)
    h = k32.OpenProcess(mask, False, PID)
    err = ctypes.get_last_error()
    print("%-34s h=%#x err=%d" % (name, h or 0, err))
    if h:
        buf = ctypes.create_string_buffer(8)
        got = ctypes.c_size_t()
        ok = k32.ReadProcessMemory(ctypes.c_void_p(h), ctypes.c_void_p(0x140000000),
                                   buf, 8, ctypes.byref(got))
        print("    ReadProcessMemory ok=%d err=%d got=%d bytes=%s" %
              (bool(ok), ctypes.get_last_error(), got.value, buf.raw[:8].hex()))
        # try NtReadVirtualMemory too (different syscall path)
        b2 = ctypes.create_string_buffer(8)
        g2 = ctypes.c_size_t()
        st = ntdll.NtReadVirtualMemory(ctypes.c_void_p(h), ctypes.c_void_p(0x140000000),
                                       b2, 8, ctypes.byref(g2))
        print("    NtReadVirtualMemory status=%#x got=%d bytes=%s" %
              (st & 0xFFFFFFFF, g2.value, b2.raw[:8].hex()))
        k32.CloseHandle(h)
