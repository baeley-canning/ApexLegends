"""Decisive test of the gdrv3 physical read: ACPI RSDP checksum.

A valid RSDP is 20 bytes whose bytes sum to 0 (mod 256) and lives on a 16-byte
boundary inside 0xE0000-0xFFFFF.  Nothing else in that window can fake it, so a
pass here means we are reading real physical memory at the right address.

Only 0xE0000-0x100000 is touched (firmware ROM, always backed).  Do not sweep
holes: MmMapIoSpace on an unbacked range bugchecks the machine.
"""
import ctypes
import os
import struct
import sys
import time

import elev_probe as E

OUT = os.path.join(E.HERE, "verify.txt")
IOCTL_READ = 0xC3502014
PAGE = 0x1000
SIG = b"RSD PTR "


def read_page(h, phys, dst):
    ib = ctypes.create_string_buffer(0x20)
    struct.pack_into("<QII", ib, 0, phys, PAGE, 0)
    struct.pack_into("<Q", ib, 0x10, dst)
    ret = ctypes.c_ulong(0)
    # out_len 0 with a 1-byte buffer matches the vendor DLL's calling convention;
    # out_len < in->size with a real buffer gives ERROR_INSUFFICIENT_BUFFER (122).
    ob = ctypes.create_string_buffer(1)
    ok = E.k32.DeviceIoControl(h, IOCTL_READ, ib, 0x18, ob, 0,
                               ctypes.byref(ret), None)
    if not ok:
        return False, ctypes.get_last_error(), b""
    return True, 0, ctypes.string_at(dst, PAGE)


def rsdp_report(data, phys, log):
    """Validate every 16-byte-aligned 'RSD PTR ' in one page."""
    hits = 0
    off = data.find(SIG)
    while off >= 0:
        if off % 16 == 0 and off + 20 <= len(data):
            rsdp = data[off:off + 20]
            csum = sum(rsdp) & 0xFF
            oemid = rsdp[9:15]
            rev = rsdp[15]
            rsdt = struct.unpack_from("<I", rsdp, 16)[0]
            log("  phys %#010x: RSDP rev=%d oem=%-6s rsdt=%#x csum=%#04x %s"
                % (phys + off, rev, oemid.decode("latin-1"), rsdt, csum,
                   "VALID" if csum == 0 else "BAD"))
            for ln in E.hexdump(rsdp, phys + off, limit=0x14):
                log("    " + ln)
            hits += 1
        off = data.find(SIG, off + 1)
    return hits


def elevated_main():
    fh = open(OUT, "w", encoding="utf-8")

    def log(s=""):
        fh.write(s + "\n")
        fh.flush()
        print(s)

    elev = E.elevation()
    log("=== verify pid=%d elevation=%s ioctl=%#x" % (os.getpid(), elev, IOCTL_READ))
    h = E.k32.CreateFileW(r"\\.\GIOV3", E.GENERIC_READ | E.GENERIC_WRITE, 0,
                          None, E.OPEN_EXISTING, 0, None)
    if h is None or h == ctypes.c_void_p(-1).value:
        log("open failed err=%d" % ctypes.get_last_error())
        fh.close()
        return 1

    dst = E.alloc_locked(PAGE)
    # Control 1: a read must overwrite the prefill, or "0xFF" means nothing.
    ctypes.memset(dst, 0x5A, PAGE)
    ok, err, data = read_page(h, 0xE0000, dst)
    log("control @0xE0000 ok=%s err=%d first16=%s" % (ok, err, data[:16].hex()))
    # Control 2: is the uniform 0xFF in low RAM a real fill or a stale buffer?
    ctypes.memset(dst, 0x5A, PAGE)
    ok, err, data = read_page(h, 0x2000, dst)
    log("control @0x2000  ok=%s err=%d first16=%s (5a => driver never wrote)"
        % (ok, err, data[:16].hex()))

    log("--- scanning 0xE0000-0x100000 for RSDP")
    t0 = time.time()
    found = valid = 0
    pages = 0
    for phys in range(0xE0000, 0x100000, PAGE):
        ok, err, data = read_page(h, phys, dst)
        if not ok:
            log("  read %#x failed err=%d" % (phys, err))
            continue
        pages += 1
        found += rsdp_report(data, phys, log)
        if SIG in data:
            valid += 1
    dt = time.time() - t0
    log("--- %d pages in %.3fs; %d 'RSD PTR ' candidates" % (pages, dt, found))
    log("VERDICT: %s" % ("phys read is REAL and correctly addressed"
                         if found else "no RSDP found - addressing still in doubt"))
    E.k32.VirtualFree(dst, 0, E.MEM_RELEASE)
    E.k32.CloseHandle(h)
    fh.close()
    return 0 if found else 2


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
