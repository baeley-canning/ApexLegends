"""Frame 0x436ad8000 answers 1450 = ERROR_NO_SYSTEM_RESOURCES on every 4 KB read
while its neighbours read fine.  That code is MmMapIoSpace refusing the request,
not "no such page" - the usual cause is asking for 4 KB inside a range that is
mapped with 2 MB pages.  So try the same frame in other shapes: 2 MB-aligned
2 MB read, 64 KB read, 4 KB read, and the next frame, each on its own fresh
handle.  Read-only.

If a shape works, that shape is the page-table read primitive (dtb 0x436ad8000
currently blocks every Walk / translate).
"""
import ctypes
import sys

import numpy as np

sys.path.insert(0, "..\\ext")
import gio
import dumplive as dl

FRAME = 0x436ad8000
BIG = FRAME & ~0x1FFFFF
OUT = "_shape_out.txt"
log = open(OUT, "w", encoding="utf-8")


def say(s):
    log.write(s + "\n")
    log.flush()


def try_shape(pa, size, tries=3):
    g = None
    try:
        g = gio.Gio(chunk=min(size, 0x1000))
        for _k in range(tries):
            try:
                b = g.read_phys(pa, size)
                return b, ""
            except OSError as e:
                err = str(e)
        return None, err
    except OSError as e:
        return None, "open: %s" % e
    finally:
        if g is not None:
            try:
                g.close()
            except Exception:
                pass


def pte_probe(b, base, frame):
    pl = b[frame - base:frame - base + 0x1000]
    si = (frame >> 39) & 0x1FF
    return int(np.frombuffer(pl, "<u8")[si])


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % __file__))
        return 0
    say("=== frame shapes %#x (2MB base %#x) ===" % (FRAME, BIG))
    for label, pa, size in (("2MB-aligned 2MB", BIG, 0x200000),
                            ("4KB frame", FRAME, 0x1000),
                            ("64KB frame", FRAME, 0x10000),
                            ("4KB frame+1", FRAME + 0x1000, 0x1000),
                            ("2MB base 4KB", BIG, 0x1000),
                            ("64KB frame-4K", FRAME - 0x1000, 0x10000)):
        b, err = try_shape(pa, size)
        if b is None:
            say("  %-16s %#x+%#x: %s" % (label, pa, size, err))
            continue
        si = (FRAME >> 39) & 0x1FF
        v = (pte_probe(b, pa, FRAME) if pa <= FRAME < pa + len(b) else 0)
        selfref = "self-ok" if (v & ~0xFFF) == FRAME else "pm[%d]=%#x" % (si, v)
        say("  %-16s %#x+%#x: READ %d bytes, %s" % (label, pa, size, len(b), selfref))
    say("RESULT: frame=%#x pml4-index=%d" % (FRAME, (FRAME >> 39) & 0x1FF))
    say("VERDICT: see lines above")
    return 0


if __name__ == "__main__":
    sys.exit(main())
