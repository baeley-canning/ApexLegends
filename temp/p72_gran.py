r"""p72_gran.py -- is the DTB frame only unreadable at 4 KiB granularity?
Read-only.  Tries the same page at 2M/64K/4K alignment and its neighbours.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio

OUT = os.path.join(HERE, "_p72_gran.txt")
TRIES = [
    ("4k exact", 0x514c3e000, 0x40),
    ("4k prev ", 0x514c3d000, 0x40),
    ("4k next ", 0x514c3f000, 0x40),
    ("64k page", 0x514c00000, 0x40),
    ("64k mid ", 0x514c40000, 0x40),
    ("2m base ", 0x514c00000, 0x200000),
    ("1m base ", 0x514c00000, 0x100000),
]


def main():
    lines = []
    try:
        g = gio.Gio()
    except Exception:
        import traceback
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("Gio() open failed\n" + traceback.format_exc())
        return 3
    try:
        for tag, pa, n in TRIES:
            try:
                blk = g.read_phys(pa, n)
                tail = blk[:8].hex()
                lines.append("%s %#011x+%#x ok %s" % (tag, pa, n, tail))
            except Exception as e:
                lines.append("%s %#011x+%#x FAIL %r"
                             % (tag, pa, n, e))
            with open(OUT, "w", encoding="utf-8") as f:
                f.write("\n".join(lines) + "\n")
    finally:
        g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
