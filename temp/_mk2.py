"""h34x: does the read struct's pad field change the outcome on a dead PFN?

read = memcpy(dst, MmMapIoSpace(pa, size, <cache>), size).  pad is the only
input never varied; MEMORY_CACHING_TYPE is MmNonCached=0, MmCached=1,
MmWriteCombined=2, MmHardwareCoherentCached=3, MmNonCachedUnordered=4.
Tiny sizes included to prove there is no small-read branch.  Read-only.
"""
import ctypes
import os
import struct
import sys

sys.path.insert(0, "..\\ext")
import dumplive as dl          # noqa: E402
import gio                     # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_mk2_out.txt")
FRAME = 0x6EF568000
CTRL = 0x436A00000
GOOD = 0x6EF980000


def say(s):
    line = str(s)
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def rd(g, pa, n, pad=0):
    ib = struct.pack("<QIIQ", pa, n, pad, g.dst)
    ok, err, _, got = g._ioctl(gio.IOCTL_READ, ib, 0)
    if not ok:
        return "ERR %s" % err
    return "ok %s" % ctypes.string_at(g.dst, min(n, 8)).hex()


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % __file__))
        return 0
    open(OUT, "w").close()
    g = gio.Gio(chunk=0x1000)

    say("--- tiny sizes (pad=0), no-branch proof ---")
    for n in (8, 16, 64, 512, 0x800):
        say("  frame %#012x size %#05x -> %s" % (FRAME, n, rd(g, FRAME, n)))

    say("--- pad sweep: cache type ---")
    for pad in (0, 1, 2, 3, 4):
        say("  frame pad=%d -> %s" % (pad, rd(g, FRAME, 0x1000, pad)))
        say("  ctrl  pad=%d -> %s" % (pad, rd(g, CTRL, 0x1000, pad)))
        say("  good  pad=%d -> %s" % (pad, rd(g, GOOD, 0x1000, pad)))

    say("--- span: good page overlapping into dead frame ---")
    say("  0x6ef567000+0x2000 -> %s" % rd(g, FRAME - 0x1000, 0x2000))
    say("  RESULT: pad sweep done; any 'ok' on frame = workaround found")
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
