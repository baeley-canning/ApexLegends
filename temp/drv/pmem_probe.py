"""pmem_probe.py -- live test of the gdrv3 (GIOV3) physical-memory read IOCTL.

Recovered handler (gdrv3.sys RVA ~0x3696):
    if (in_len < 0x18) return STATUS_INSUFFICIENT_RESOURCES (0xC000009A)
    mapped = MmMapIoSpace(in->phys, in->size, MmNonCached(0))
    if (!mapped) return 0xC000009A
    memcpy(in->dst, mapped, in->size)
    MmUnmapIoSpace(mapped, in->size)

    struct GIOV3_READ { u64 phys; u32 size; u32 pad; void *dst; };  // 24 bytes

IOCTL 0xC3502400 -> DeviceType 0xC350, Function 0x900, METHOD_BUFFERED,
FILE_ANY_ACCESS.

This probe enumerates DOS device names, opens the device, reads known physical
regions (IVT, BDA, EBDA, VGA, LAPIC) into a locked user buffer, hexdumps them,
re-checks one read for consistency and confirms the handler rejects a short
input buffer.
"""
import ctypes
import os
import struct
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "pmem_probe.txt")

k32 = ctypes.WinDLL("kernel32", use_last_error=True)

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
FILE_SHARE_RW = 0x00000003
OPEN_EXISTING = 3
INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value
MEM_COMMIT = 0x1000
MEM_RESERVE = 0x2000
MEM_RELEASE = 0x8000
PAGE_READWRITE = 0x04

k32.CreateFileW.restype = wintypes.HANDLE
k32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                             wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD,
                             wintypes.HANDLE]
k32.DeviceIoControl.restype = wintypes.BOOL
k32.DeviceIoControl.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPVOID,
                                 wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD,
                                 ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
k32.QueryDosDeviceW.restype = wintypes.DWORD
k32.QueryDosDeviceW.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR, wintypes.DWORD]
k32.VirtualAlloc.restype = wintypes.LPVOID
k32.VirtualAlloc.argtypes = [wintypes.LPVOID, ctypes.c_size_t, wintypes.DWORD,
                              wintypes.DWORD]
k32.VirtualLock.restype = wintypes.BOOL
k32.VirtualLock.argtypes = [wintypes.LPVOID, ctypes.c_size_t]
k32.VirtualFree.restype = wintypes.BOOL
k32.VirtualFree.argtypes = [wintypes.LPVOID, ctypes.c_size_t, wintypes.DWORD]

IOCTL_MAP_READ = 0xC3502400          # gdrv3 MmMapIoSpace + memcpy
DEVICE_CANDIDATES = [r"\\.\GIOV3", r"\\.\gdrv3", r"\\.\giov3",
                     r"\\.\GIOV3_0", r"\\.\GBTEC"]

lines = []


def log(s=""):
    lines.append(s)
    print(s)


def dos_devices():
    """All DOS device names -> target, filtered for anything gdrv/GIOV-ish."""
    buf = ctypes.create_unicode_buffer(1 << 20)
    n = k32.QueryDosDeviceW(None, buf, len(buf))
    if not n:
        return []
    names = buf[:n].split("\x00")
    out = []
    for nm in names:
        if not nm:
            continue
        low = nm.lower()
        if "gio" in low or "gdrv" in low or "gigabyte" in low or "gbt" in low:
            tgt = ctypes.create_unicode_buffer(1024)
            k32.QueryDosDeviceW(nm, tgt, len(tgt))
            out.append((nm, tgt.value))
    return out


def open_device(name):
    h = k32.CreateFileW(name, GENERIC_READ | GENERIC_WRITE,
                        FILE_SHARE_RW, None, OPEN_EXISTING, 0, None)
    if not h or h == INVALID_HANDLE_VALUE:
        return None, ctypes.get_last_error()
    return h, 0


def alloc_locked(size):
    """Committed, touched, locked buffer so kernel memcpy to it cannot fault."""
    p = k32.VirtualAlloc(None, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE)
    if not p:
        raise OSError(ctypes.get_last_error(), "VirtualAlloc")
    ctypes.memset(p, 0xCC, size)                  # fault every page in
    k32.VirtualLock(p, size)
    return p


def ioctl_map_read(h, phys, size, dst, in_len=24, out_len=0):
    """One 0xC3502400 call.  Struct goes in the *input* buffer."""
    ib = ctypes.create_string_buffer(in_len)
    struct.pack_into("<QII", ib, 0, phys & 0xFFFFFFFFFFFFFFFF, size, 0)
    if in_len >= 0x18:
        struct.pack_into("<Q", ib, 0x10, dst)
    ob = ctypes.create_string_buffer(max(out_len, 1))
    ret = wintypes.DWORD(0)
    ok = k32.DeviceIoControl(h, IOCTL_MAP_READ, ib, in_len,
                             ob, out_len, ctypes.byref(ret), None)
    err = 0 if ok else ctypes.get_last_error()
    return bool(ok), err, ret.value, ob.raw


def hexdump(data, base=0, width=16, limit=None):
    out = []
    n = len(data) if limit is None else min(limit, len(data))
    for off in range(0, n, width):
        chunk = data[off:off + width]
        hx = " ".join("%02x" % b for b in chunk).ljust(width * 3 - 1)
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        out.append("  %08x  %s  |%s|" % (base + off, hx, asc))
    return out


def read_phys(h, phys, size):
    dst = alloc_locked(size)
    try:
        ok, err, ret, _ = ioctl_map_read(h, phys, size, dst)
        data = ctypes.string_at(dst, size) if ok else b""
        return ok, err, ret, data
    finally:
        k32.VirtualFree(dst, 0, MEM_RELEASE)


def main():
    log("=== dos devices (filtered)")
    for nm, tgt in dos_devices():
        log("  %-20s -> %s" % (nm, tgt))

    handle = None
    used = None
    log("=== CreateFileW")
    for cand in DEVICE_CANDIDATES:
        h, err = open_device(cand)
        if h:
            log("  %-16s OK   handle=%#x" % (cand, h))
            if handle is None:
                handle, used = h, cand
        else:
            log("  %-16s FAIL err=%d (%s)"
                % (cand, err, ctypes.FormatError(err).strip()))
    if not handle:
        log("no device opened -- stopping")
        return

    log("=== IOCTL %#010x (%s)" % (IOCTL_MAP_READ, used))
    probes = [("IVT/low RAM", 0x00000000, 0x200),
              ("BDA-ish", 0x00000400, 0x200),
              ("low RAM", 0x00001000, 0x100),
              ("EBDA", 0x0009F000, 0x100),
              ("BIOS F-seg", 0x000FFF00, 0x100),
              ("VGA", 0x000A0000, 0x100),
              ("LAPIC", 0xFEE00000, 0x40)]
    results = []
    for label, phys, size in probes:
        ok, err, ret, data = read_phys(handle, phys, size)
        nz = sum(1 for b in data if b)
        log("  %-12s phys=%#012x size=%#06x ok=%s err=%d ret=%d nonzero=%d/%d"
            % (label, phys, size, ok, err, ret, nz, size))
        if ok and nz and label in ("IVT/low RAM", "BIOS F-seg", "LAPIC"):
            lines.extend(hexdump(data, phys, limit=0x60))
        results.append((label, phys, size, ok, data))

    ok1, _, _, d1 = read_phys(handle, 0x00000000, 0x200)
    ok2, _, _, d2 = read_phys(handle, 0x00000000, 0x200)
    log("=== consistency 0x0 x2: ok=%s/%s identical=%s"
        % (ok1, ok2, bool(d1) and d1 == d2))

    dst = alloc_locked(0x100)
    ok, err, ret, _ = ioctl_map_read(handle, 0x1000, 0x100, dst, in_len=8)
    log("=== short in_len=8 -> ok=%s err=%d (%s)"
        % (ok, err, ctypes.FormatError(err).strip()))
    k32.VirtualFree(dst, 0, MEM_RELEASE)

    good = sum(1 for r in results if r[3])
    log("=== %d/%d reads accepted" % (good, len(results)))
    if good:
        log("VERDICT: gdrv3 phys-read primitive is LIVE via %s" % used)
    else:
        log("VERDICT: device opened but IOCTL rejected -- code/struct mismatch")


try:
    main()
finally:
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
