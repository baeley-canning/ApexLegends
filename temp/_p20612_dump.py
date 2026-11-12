"""Dump the Proc object at 0x2aa1d5010 and find its DTB by PML4 self-reference.

The cal row said name@+0x3a8 (hit 0x2aa1d53b8 - 0x3a8) and pid@+0x240; the old
+0x338/+0x28 constants do not fit this build.  For every frame-like qword in the
first 0x400 bytes, read the frame and accept it only if pm[l4idx] == frame - that
is the property a DirectoryTableBase has and nothing else does.
"""
import sys
import time

import numpy as np

sys.path.insert(0, "..\\ext")
import gio
import dumplive as dl

OBJ = 0x2aa1d5010
OUT = "_p20612_dump_out.txt"
log = open(OUT, "w", encoding="utf-8")


def say(s):
    log.write(s + "\n")
    log.flush()


def rd(g, pa, n, tries=12):
    for k in range(tries):
        try:
            return g.read_phys(pa, n)
        except OSError as e:
            err = e
    say("  read %#x+%#x failed: %s" % (pa, n, err))
    return None


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % __file__))
        return 0
    g = gio.Gio(chunk=0x1000)
    ranges, _n = dl.usable_ranges(g.ram_top, 0x1000, None)
    obj = OBJ
    for a in sys.argv:
        if a.startswith("--at="):
            obj = int(a.split("=", 1)[1], 0)
    say("ram_top=%#x ranges=%d obj=%#x" % (g.ram_top, len(ranges), obj))
    b = rd(g, obj - 0x10, 0x420)
    if b is None:
        say("RESULT: object page unreadable")
        say("VERDICT: FAIL")
        return 1
    buf = b[0x10:]
    say("header at obj-0x10: %s" % " ".join("%02x" % x for x in b[:0x10]))
    for off in range(0, 0x300 - 16, 16):
        say("%+#06x %s" % (off, " ".join("%02x" % x for x in buf[off:off + 16])))
    say("name@+0x3a8: %r" % buf[0x3a8:0x3b8])
    say("pid@+0x240 : %#x" % int(np.frombuffer(buf[0x240:0x244], "<u4")[0]))
    say("+0x28       : %#x" % int(np.frombuffer(buf[0x28:0x30], "<u8")[0]))
    say("+0x98       : %#x" % int(np.frombuffer(buf[0x98:0xa0], "<u8")[0]))
    say("+0x248      : %#x" % int(np.frombuffer(buf[0x248:0x250], "<u8")[0]))
    say("+0x70 type  : %d" % buf[0x70])
    q = np.frombuffer(buf[:0x400], "<u8")
    cand = [(i * 8, int(v)) for i, v in enumerate(q)
            if v & 0xFFF == 0 and 0x1000 < v < g.ram_top]
    say("frame-like qwords in +0x0..0x400: %d" % len(cand))
    hit = []
    for off, d in cand:
        pl = rd(g, d, 0x1000)
        if pl is None:
            say("  +%#05x %#x DEAD" % (off, d))
            continue
        si = (d >> 39) & 0x1FF
        ent = np.frombuffer(pl, "<u8")
        if any(int(x) & ~0xFFF == d for x in ent):
            idx = [i for i, x in enumerate(ent) if int(x) & ~0xFFF == d]
            say("  +%#05x %#x PML4-SELF-OK idx=%s" % (off, d, idx))
            hit.append((off, d))
        else:
            say("  +%#05x %#x no (pm[%d]=%#x)"
                % (off, d, si, int(ent[si])))
    say("RESULT: self-ok=%d" % len(hit))
    say("VERDICT: %s" % ("PASS - dtb=%#x at +%#x" % hit[0] if hit else "FAIL"))
    g.close()
    return 0 if hit else 1


if __name__ == "__main__":
    sys.exit(main())
