"""Address-semantics probe for gdrv3 0xC3502014.

Only a few pages are touched, all of them candidates for real firmware/RAM, so
this cannot hit an unbacked hole the way a blind sweep does.

Questions:
  1. Is `phys` a byte address?   -> 0x1000 vs 0x1004 vs 0x1008 must differ
                                     by exactly 4 bytes.
  2. Is it a page-frame number?   -> phys 0x1 should reproduce phys 0x1000.
  3. Does the driver honour `size` -> 0x1000 bytes vs 0x100 bytes at 0x1000.
"""
import ctypes
import os
import struct
import sys

import elev_probe as E

OUT = os.path.join(E.HERE, "probe_addr.txt")
IOCTL_READ = 0xC3502014


def rd(h, phys, size, dst):
    ib = ctypes.create_string_buffer(0x20)
    struct.pack_into("<QII", ib, 0, phys, size, 0)
    struct.pack_into("<Q", ib, 0x10, dst)
    ob = ctypes.create_string_buffer(1)
    ret = ctypes.c_ulong(0)
    ok = E.k32.DeviceIoControl(h, IOCTL_READ, ib, 0x18, ob, 0,
                                ctypes.byref(ret), None)
    if not ok:
        return False, ctypes.get_last_error(), b""
    return True, 0, ctypes.string_at(dst, size)


def elevated_main():
    fh = open(OUT, "w", encoding="utf-8")

    def log(s=""):
        fh.write(s + "\n")
        fh.flush()
        print(s)

    log("=== probe_addr pid=%d elevation=%s" % (os.getpid(), E.elevation()))
    h = E.k32.CreateFileW(r"\\.\GIOV3", E.GENERIC_READ | E.GENERIC_WRITE, 0,
                          None, E.OPEN_EXISTING, 0, None)
    if not h or h == ctypes.c_void_p(-1).value:
        log("open failed err=%d" % ctypes.get_last_error())
        fh.close()
        return 1
    dst = E.alloc_locked(0x2000)

    tests = [
        (0x1000, 0x40, "known-good page"),
        (0x1004, 0x40, "byte addressing? expect shift of 4"),
        (0x1008, 0x40, "byte addressing? expect shift of 8"),
        (0x1, 0x40, "PFN theory: expect == 0x1000 data"),
        (0x2, 0x40, "PFN theory: expect 0xFF"),
        (0x100, 0x40, "PFN theory: expect 0x100000 data"),
        (0x100000, 0x40, "1 MiB: real RAM?"),
        (0xFFFE0, 0x20, "reset vector jmp?"),
        (0x400, 0x40, "BDA"),
    ]
    for phys, size, why in tests:
        ctypes.memset(dst, 0x5A, 0x2000)
        ok, err, data = rd(h, phys, size, dst)
        log("phys %#010x size %#05x ok=%s err=%d  (%s)" % (phys, size, ok, err, why))
        if ok:
            for ln in E.hexdump(data, phys, limit=size):
                log("    " + ln)

    # size coherence: 0x1000 bytes from 0x1000 must contain the same first 0x40
    ctypes.memset(dst, 0x5A, 0x2000)
    ok, err, big = rd(h, 0x1000, 0x1000, dst)
    ok2, err2, small = rd(h, 0x1000, 0x40, dst)
    log("size check: big=%s(%d) small=%s(%d) prefix_match=%s"
        % (ok, err, ok2, err2, ok and ok2 and big[:0x40] == small))

    E.k32.VirtualFree(dst, 0, E.MEM_RELEASE)
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
