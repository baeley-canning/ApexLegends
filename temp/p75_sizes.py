r"""p75_sizes.py -- does the failing frame read at other sizes / offsets / times?

p74 isolated the fault to one page: 0x4a6be3000 faults 1450 while all eight
neighbours read, and one historical Apex DTB reads while another faults.
map_phys fails on the same page, so the driver's mapping of that PA is what
refuses -- not the caller's loop.

Parts:
  A  failing page at 8/0x20/0x100/0x400/0x800/0x1000 bytes  (size ladder)
  B  control page at the same sizes                 (sizes are not the problem)
  C  failing page, 8-byte read x3 with 0.5 s pauses  (is it transient?)
  D  failing page, 8-byte reads at 8 offsets        (is it the bytes?)
  E  the second old Apex DTB at 8 bytes             (same answer elsewhere)
  F  a 0x2000 window centred on the page            (fault only when spanned?)

A working small size is a walker workaround: a PML4/PDPT/PD read needs qwords,
not a whole page.  Read-only, one handle, no mappings kept.
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio  # noqa: E402

OUT = os.path.join(HERE, "_p75_sizes.txt")
BAD = 0x4A6BE3000
CTL = 0x4A3410000
OLD2 = 0x514C3E000
SIZES = (8, 0x20, 0x100, 0x400, 0x800, 0x1000)


def log(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")
    print(s)


def rd(g, pa, n):
    try:
        g.read_phys(pa, n)
        return "OK"
    except OSError as e:
        return "err %d %#x" % (e.args[0] if e.args else -1,
                               e.args[0] if e.args else -1)


def main():
    if os.path.exists(OUT):
        os.remove(OUT)
    log("p75 sizes")
    with gio.Gio() as g:
        for tag, pa in (("A", BAD), ("B", CTL)):
            for n in SIZES:
                log("%s %#x size=%#6x -> %s" % (tag, pa, n, rd(g, pa, n)))
        for i in range(3):
            log("C %#x try=%d size=8 -> %s" % (BAD, i + 1, rd(g, BAD, 8)))
            time.sleep(0.5)
        for off in (0, 8, 16, 0x100, 0x3F8, 0x800, 0xFF0, 0xFF8):
            log("D %#x -> %s" % (BAD + off, rd(g, BAD + off, 8)))
        log("E %#x size=8 -> %s" % (OLD2, rd(g, OLD2, 8)))
        log("F %#x size=0x2000 -> %s" % (BAD - 0x1000, rd(g, BAD - 0x1000, 0x2000)))
    log("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
