r"""p73_pt.py -- dump a candidate table page: 512 qwords, decoded three ways.
Read-only diagnostic.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio

OUT = os.path.join(HERE, "_p73_pt.txt")
PAGES = [int(a, 0) for a in sys.argv[1:]] or [0x6C6B38000]


def main():
    lines = []
    g = gio.Gio()
    try:
        for page in PAGES:
            lines.append("=== page %#x ram=%s" % (page, g.is_ram(page)))
            try:
                blk = g.read_phys(page, 0x1000)
            except OSError as e:
                lines.append("  DEAD %r" % (e,))
                continue
            nz = 0
            for i in range(0, 512):
                q = struct.unpack_from("<Q", blk, i * 8)[0]
                if not q:
                    continue
                nz += 1
                if nz <= 40:
                    lines.append("  [%3d] %#018x lo12=%#05x pfn12=%#x "
                                 "ram=%s"
                                 % (i, q, q & 0xFFF, (q >> 12) & 0xFFFFF,
                                    g.is_ram((q >> 12) << 12)))
            lines.append("  nonzero=%d of 512" % nz)
            lines.append("  head " + blk[:0x40].hex())
    finally:
        g.close()
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
