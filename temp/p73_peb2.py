r"""p73_peb2.py -- read the PEB page EP+0x2e0 pointed at.  Read-only."""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio

OUT = os.path.join(HERE, "_p73_peb2.txt")
PAGE = 0x1000
CAND = [0x364000, 0x1243784124 & ~0xFFF]


def main():
    lines = []
    g = gio.Gio()
    try:
        for va in CAND:
            lines.append("--- va=%#x ram=%s" % (va, g.is_ram(va & ~0xFFF)))
            try:
                blk = g.read_phys(va & ~0xFFF, 0x40)
            except OSError as e:
                lines.append("  read FAIL %r" % (e,))
                continue
            lines.append("  head " + blk.hex())
            for off in (0x08, 0x10, 0x18, 0x20):
                lines.append("  +%#04x %#x" % (off, struct.unpack_from("<Q", blk, off)[0]))
    except Exception:
        import traceback
        lines.append("EXC\n" + traceback.format_exc())
    finally:
        g.close()
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
