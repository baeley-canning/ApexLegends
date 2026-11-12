r"""h405 -- open ALREADY RUNNING drivers, no load, no game mutations.
Inspect IOCTL families backed by current driver, signature for PT query.
This never guesses or pokes arbitrary physical addresses.
"""
import ctypes as C
import os
import struct
import time

k=C.WinDLL('kernel32',use_last_error=True)
k.CreateFileW.restype=C.c_void_p
k.CreateFileW.argtypes=[C.c_wchar_p,C.c_ulong,C.c_ulong,C.c_void_p,C.c_ulong,
                         C.c_ulong,C.c_void_p]
for name in (r"\\.\DBUtilDrv2",r"\\.\DBUTIL",r"\\.\GIOV3",r"\\.\MsIo"):
    h=k.CreateFileW(name,0xC0000000,0,None,3,0,None)
    print("device",name,"handle",hex(h or 0),"error",C.get_last_error())
    if h and h!=C.c_void_p(-1).value:k.CloseHandle(h)