"""Validate kx.image_info() against real modules in our own process.

image_info() only needs an object with .read(addr, size) -> (bytes, err), so we
can feed it ReadProcessMemory on the current process and check that it parses
PE32+ headers and recovers the CodeView PDB path.
"""
import ctypes
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kx

k32 = kx.k32
k32.GetModuleHandleW.argtypes = [ctypes.c_wchar_p]
k32.GetModuleHandleW.restype = ctypes.c_void_p


class SelfReader:
    def __init__(self):
        self.h = k32.GetCurrentProcess()

    def read(self, addr, size):
        buf = (ctypes.c_char * size)()
        got = ctypes.c_size_t(0)
        ok = k32.ReadProcessMemory(self.h, ctypes.c_void_p(addr), buf, size,
                                   ctypes.byref(got))
        if not ok or got.value == 0:
            return None, ctypes.get_last_error()
        return bytes(buf)[:got.value], 0


def main():
    rd = SelfReader()
    rc = 0
    for name in (None, "kernel32.dll", "ntdll.dll"):
        base = k32.GetModuleHandleW(name)
        if not base:
            print("skip %s (not loaded)" % name)
            continue
        info = kx.image_info(rd, base)
        if not info:
            print("FAIL %s: no PE parsed at %#x" % (name, base))
            rc = 1
            continue
        ok = info["machine"] == 0x8664 and info["size_image"] > 0x1000
        print("%-14s base=%#x size=%#x nsec=%d pdb=%s %s"
              % (name or "self", info["base"], info["size_image"],
                 info["sections"], info["pdb"], "OK" if ok else "BAD"))
        if not ok:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
