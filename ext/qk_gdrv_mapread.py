r"""qk_gdrv_mapread -- same-IOCTL-family page read that does NOT fail on live page tables.

Should confirm gdrv3 read 0xC3502014 returns 1450 whereas 0xC3502019 actually
copies the bytes for two known deadlock cases (temp/h395_gdrv_map.txt).
Call map_kernel(pa, size, dst) with caller-owned locked buffer and copy out of
it. The returned value looks NULL in this version; there is no new virtual map.
All addresses derived from a real RAM interval set, not guessed MMIO (R10).
"""
import ctypes as C
import struct

import gio
import dumplive as dl


class Reader:
    def __init__(self, g):
        self.g = g
        k = C.WinDLL("kernel32", use_last_error=True)
        k.VirtualAlloc.argtypes = [C.c_void_p, C.c_size_t, C.c_ulong, C.c_ulong]
        k.VirtualAlloc.restype = C.c_void_p
        k.VirtualLock.argtypes = [C.c_void_p, C.c_size_t]
        self.k = k
        self.dst = k.VirtualAlloc(None, 0x1000, 0x1000 | 0x2000, 0x04)
        if not self.dst:
            raise OSError("allocation failed")
        if not k.VirtualLock(self.dst, 0x1000):
            raise OSError("lock failed: %d" % C.get_last_error())
        self.ranges, self.note = dl.usable_ranges(g.ram_top, None, None)
        self.fail = []
        self.reads = 0

    def in_ram(self, pa, size):
        return any(lo <= pa and pa + size <= hi for lo, hi in self.ranges)

    def read(self, pa, size):
        if size <= 0 or size > 0x1000:
            raise OSError(22, "MapK page reader size=%d" % size)
        if not self.in_ram(pa, size):
            raise OSError(22, "RAM interval guard rejected %#x+%#x" % (pa, size))
        self.reads += 1
        req = struct.pack("<QIIQ", pa, size, 0, self.dst)
        ok, err, _ob, got = self.g._ioctl(gio.IOCTL_MAP_K, req, 0)
        if not ok:
            self.fail.append((pa, err))
            raise OSError(err, "MapK physical read %#x+%#x failed" % (pa, size))
        return C.string_at(self.dst, size)

    def close(self):
        if self.dst:
            self.k.VirtualFree(C.c_void_p(self.dst), 0, 0x8000)
            self.dst = None


def install(g):
    """gdrv3 with the MapK page-read replacement; keeps caching and RAM guards."""
    reader = Reader(g)
    g.mapread = reader
    g.read_phys = reader.read
    return reader