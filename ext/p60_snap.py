r"""p60_snap.py -- dump the memory neighbourhood of the p60 name hits.

Usage: python ext\p60_snap.py <label> [hitsfile]
Writes temp\p60_snap_<label>.txt as  addr value  lines (nonzero dwords only),
so a before/after pair can be diffed for the health field.
Read-only; every page comes out of a successful read, so nothing can bugcheck.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gio import Gio, PAGE  # noqa: E402

ROOT = os.path.dirname(HERE)


def hit_pages(path):
    pages = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if not line.startswith("HIT "):
                continue
            a = int(line.split("addr=")[1], 16)
            p = a & ~0xFFF
            if p not in pages:
                pages.append(p)
    return pages


def main(argv):
    label = argv[0]
    src = argv[1] if len(argv) > 1 else os.path.join(ROOT, "temp", "p60_name_ascii.txt")
    pages = hit_pages(src)
    out = os.path.join(ROOT, "temp", "p60_snap_%s.txt" % label)
    g = Gio()
    try:
        with open(out, "w", encoding="ascii") as h:
            h.write("# snap %s pages=%d src=%s\n" % (label, len(pages), os.path.basename(src)))
            for p in pages[:80]:
                for off in range(-PAGE, PAGE * 2, PAGE):
                    pa = p + off
                    try:
                        buf = g.read_phys(pa, PAGE)
                    except OSError:
                        continue
                    for i in range(0, PAGE - 3, 4):
                        v = struct.unpack_from("<I", buf, i)[0]
                        if v:
                            f = struct.unpack_from("<f", buf, i)[0]
                            h.write("%#011x %08x %g\n" % (pa + i, v, f))
    finally:
        g.close()
    print("SNAP label=%s pages=%d out=%s" % (label, len(pages), out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
