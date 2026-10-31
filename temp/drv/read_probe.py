"""read_probe.py -- resolve WHERE IOCTL 0xC3502400 actually lands its data.

elev_probe.py showed 7/7 "success" but every dst page read back as zeros.  That
is ambiguous: the destination was a fresh VirtualAlloc (already zero), so
"never written" and "written real zeros" look identical.

This probe pre-fills dst with 0xAA and dumps BOTH the dst buffer and the
DeviceIoControl output buffer (the METHOD_BUFFERED SystemBuffer).  Whichever one
changed is the real destination.

It also cross-checks 0xC3502014 (same {phys,size,dst} shape per the DLL) and
0xC350280C (linear -> physical translation) so a known user page can be read
back and compared byte-for-byte.  Reuses elevation/open helpers from elev_probe.
"""
import ctypes
import os
import struct
import sys
from ctypes import wintypes

import elev_probe as E

OUT = os.path.join(E.HERE, "read_probe.txt")
PATTERN = b"CLINE-PHYS-READ-PROBE-0123456789" * 4      # 128 bytes, 0x80

IOCTL_CANDIDATES = [("0x2400", 0xC3502400),
                    ("0x2014", 0xC3502014)]
IOCTL_ALLOC = 0xC3502800
IOCTL_FREE = 0xC3502804
IOCTL_TRANSLATE = 0xC350280C


def raw_ioctl(h, code, in_bytes, out_len):
    ib = ctypes.create_string_buffer(in_bytes, max(len(in_bytes), 1))
    ob = ctypes.create_string_buffer(max(out_len, 1))
    ret = wintypes.DWORD(0)
    ok = E.k32.DeviceIoControl(h, code, ib, len(in_bytes), ob, out_len,
                               ctypes.byref(ret), None)
    err = 0 if ok else ctypes.get_last_error()
    return bool(ok), err, ret.value, ob.raw[:max(out_len, 1)]


def bad_buf(size, fill=0xAA):
    """Locked, non-zeroed destination so a silent non-write is visible."""
    p = E.alloc_locked(size)
    ctypes.memset(p, fill, size)
    return p


def open_gdrv():
    for av in (E.GENERIC_READ | E.GENERIC_WRITE, 0):
        h = E.k32.CreateFileW(r"\\.\GIOV3", av, 3, None, E.OPEN_EXISTING, 0, None)
        if h and h != E.INVALID_HANDLE_VALUE:
            return h
    return None


def probe_read(h, log):
    for name, code in IOCTL_CANDIDATES:
        log("--- code %s: {u64 phys; u32 size; u32 pad; void *dst}" % name)
        for phys, size in ((0x400, 0x100), (0xF0000, 0x100)):
            dst = bad_buf(size)
            inb = struct.pack("<QIIQ", phys, size, 0, dst)
            ok, err, ret, ob = raw_ioctl(h, code, inb, size)
            got = ctypes.string_at(dst, size)
            touched = got != b"\xaa" * size
            log("  phys=%#x size=%#x ok=%-5s err=%-3d bytes_ret=%#x dst_touched=%-5s "
                "dst_nonzero=%d ob_nonzero=%d"
                % (phys, size, ok, err, ret, touched,
                   sum(1 for b in got if b), sum(1 for b in ob if b)))
            if touched:
                for ln in E.hexdump(got, phys, limit=0x20):
                    log("    dst " + ln)
            if any(ob):
                for ln in E.hexdump(ob, 0, limit=0x20):
                    log("    out " + ln)
            if touched and phys == 0x400:
                kb = struct.unpack_from("<H", got, 0x13)[0]
                log("    BDA 0x413 = %#x KB" % kb)
            E.k32.VirtualFree(dst, 0, E.MEM_RELEASE)


def probe_translate(h, log):
    log("--- 0x280C translate: in u64 VA -> out u64 PA")
    va = bad_buf(0x1000)
    ctypes.memmove(va, PATTERN, len(PATTERN))
    ok, err, ret, ob = raw_ioctl(h, IOCTL_TRANSLATE, struct.pack("<Q", va), 8)
    pa = struct.unpack_from("<Q", ob, 0)[0]
    log("  va=%#x ok=%s err=%d bytes_ret=%#x -> pa=%#x" % (va, ok, err, ret, pa))
    if ok and pa:
        for name, code in IOCTL_CANDIDATES:
            dst = bad_buf(0x1000)
            inb = struct.pack("<QIIQ", pa, len(PATTERN), 0, dst)
            ok2, err2, ret2, ob2 = raw_ioctl(h, code, inb, len(PATTERN))
            got = ctypes.string_at(dst, len(PATTERN))
            log("  %s read of own page: ok=%s err=%d match_pattern=%s "
                "outbuf_match=%s"
                % (name, ok2, err2, got == PATTERN,
                   ob2[:len(PATTERN)] == PATTERN))
            if got != PATTERN:
                for ln in E.hexdump(got, 0, limit=0x20):
                    log("    dst " + ln)
            E.k32.VirtualFree(dst, 0, E.MEM_RELEASE)
    E.k32.VirtualFree(va, 0, E.MEM_RELEASE)


def probe_alloc(h, log):
    log("--- 0x2800 alloc: in u32 size -> out 16 bytes")
    ok, err, ret, ob = raw_ioctl(h, IOCTL_ALLOC, struct.pack("<I", 0x1000), 0x10)
    log("  ok=%s err=%d bytes_ret=%#x out=%s"
        % (ok, err, ret, " ".join("%016x" % v for v in
                                  struct.unpack_from("<QQ", ob, 0))))
    if not ok:
        return
    a, b = struct.unpack_from("<QQ", ob, 0)
    for cand, tag in ((a, "out[0]"), (b, "out[1]")):
        if not cand or cand > (1 << 46):
            continue
        dst = bad_buf(0x40)
        ok2, err2, ret2, _ = raw_ioctl(h, IOCTL_CANDIDATES[0][1],
                                       struct.pack("<QIIQ", cand, 0x40, 0, dst),
                                       0x40)
        got = ctypes.string_at(dst, 0x40)
        log("  read back %s=%#x: ok=%s err=%d touched=%s nonzero=%d"
            % (tag, cand, ok2, err2, got != b"\xaa" * 0x40,
               sum(1 for x in got if x)))
        E.k32.VirtualFree(dst, 0, E.MEM_RELEASE)
    okf, errf, retf, _ = raw_ioctl(h, IOCTL_FREE, struct.pack("<QQ", a, b), 0x10)
    log("  free: ok=%s err=%d bytes_ret=%#x" % (okf, errf, retf))


def elevated_main():
    fh = open(OUT, "w", encoding="utf-8")

    def log(s=""):
        fh.write(s + "\n")
        fh.flush()
        print(s)

    log("=== read_probe pid=%d elevation=%s" % (os.getpid(), E.elevation()))
    h = open_gdrv()
    if not h:
        log("cannot open \\\\.\\GIOV3 err=%d" % ctypes.get_last_error())
        fh.close()
        return 1
    log("handle=%#x" % h)
    probe_read(h, log)
    probe_translate(h, log)
    probe_alloc(h, log)
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
