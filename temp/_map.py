"""Is gdrv3's map IOCTL (IOCTL_MAP_EX) usable where MmMapIoSpace refuses?

read_phys of 0x436ad8000 always answers 1450 while its 2 MB block's first page
reads, so the page itself is wanted by the Walk/translate and cannot be fetched.
map_phys is a different code path (section-style).  Control first: a page that
reads fine.  Then the two dead shapes.  Unmap everything.
"""
import ctypes
import sys

import numpy as np

sys.path.insert(0, "..\\ext")
import gio
import dumplive as dl

OUT = "_map_out.txt"
log = open(OUT, "w", encoding="utf-8")


def say(s):
    log.write(s + "\n")
    log.flush()


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % __file__))
        return 0
    g = gio.Gio()
    for label, pa, size in (("control 0x436a00000", 0x436a00000, 0x1000),
                            ("dtb 0x436ad8000", 0x436ad8000, 0x1000),
                            ("2MB block", 0x436a00000, 0x200000)):
        try:
            va = g.map_phys(pa, size)
        except OSError as e:
            say("  %-20s %#x+%#x MAP FAIL %s" % (label, pa, size, e))
            continue
        say("  %-20s %#x+%#x MAP OK va=%#x" % (label, pa, size, va))
        try:
            if size >= 0x1000:
                buf = ctypes.string_at(va, 0x1000)
                nz = sum(1 for x in buf[:0x40] if x)
                say("      head nonzero=%d first qwords %s"
                    % (nz, " ".join("%#x" % x for x in np.frombuffer(buf[:0x40], "<u8"))))
            if pa <= 0x436ad8000 < pa + size:
                off = 0x436ad8000 - pa
                ent = ctypes.string_at(va + off, 0x1000)
                v = np.frombuffer(ent, "<u8")
                selfref = [i for i, x in enumerate(v) if (int(x) & ~0xFFF) == 0x436ad8000]
                say("      PML4 self-entry at index %s -> %s"
                    % (selfref or "none", "DTB CONFIRMED" if selfref else "no self-ref"))
        finally:
            try:
                g.unmap(va, size)
                say("      unmapped")
            except OSError as e:
                say("      unmap FAIL %s" % e)
    say("RESULT: see lines")
    say("VERDICT: see lines")
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
