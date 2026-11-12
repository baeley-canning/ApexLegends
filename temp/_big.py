"""Single large read_phys over the dead 2 MB block.

MmMapIoSpace refuses sub-ranges inside a large-page mapping; the whole mapping
should still map.  All previous shapes issued 4 KB IOCTLs.  Try one IOCTL for
the entire block and, if that owes, one 128 KB read straddling the boundary.
"""
import ctypes
import sys

import numpy as np

sys.path.insert(0, "..\\ext")
import gio
import dumplive as dl

OUT = "_big_out.txt"
log = open(OUT, "w", encoding="utf-8")


def say(s):
    log.write(s + "\n")
    log.flush()


def try_read(g, pa, size):
    try:
        b = g.read_phys(pa, size)
    except OSError as e:
        say("  %#012x+%#08x FAIL %s" % (pa, size, e))
        return None
    v = np.frombuffer(b, "<u8")
    say("  %#012x+%#08x OK nonzero_heads=%d" % (pa, size, int(np.count_nonzero(v[:4]))))
    return b


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % __file__))
        return 0
    # chunk == request: exactly one MmMapIoSpace call of that size, not 4 KiB pieces
    g1 = gio.Gio(chunk=0x200000)
    try_read(g1, 0x436ad8000, 0x1000)              # control: known 1450
    blk = try_read(g1, 0x436a00000, 0x200000)      # whole 2 MB, ONE ioctl
    g1.close()
    g2 = gio.Gio(chunk=0x20000)
    try_read(g2, 0x436a80000, 0x20000)             # straddles the dead edge
    g2.close()
    g = g2
    if blk is not None:
        ents = np.frombuffer(blk[0xd8000:0xd9000], "<u8")
        hit = [i for i, x in enumerate(ents) if (int(x) & ~0xFFF) == 0x436ad8000]
        say("  PML4 self-entry index %s" % (hit or "none"))
        say("VERDICT: 2MB single IOCTL reads the block -- %s"
            % ("DTB page captured AND self-ref confirms PML4" if hit
               else "DTB page captured, self-ref missing (check frame)"))
    else:
        say("VERDICT: 2MB single IOCTL refused too -- frame unreachable by gdrv3")
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
