r"""p72_map.py -- does the MAP_EX path reach the DTB frame that READ cannot?
Read-only; maps one page, reads 16 bytes, unmaps.
"""
import ctypes
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio

OUT = os.path.join(HERE, "_p72_map.txt")
PA = 0x514c3e000
PAGE = 0x1000


def main():
    lines = []
    try:
        g = gio.Gio()
    except Exception:
        import traceback
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("Gio() open failed\n" + traceback.format_exc())
        return 3
    va = 0
    try:
        try:
            va = g.map_phys(PA, PAGE)
            lines.append("map_phys ok va=%#x" % va)
        except Exception as e:
            lines.append("map_phys FAIL %r" % (e,))
        if va:
            blk = ctypes.string_at(va, 16)
            lines.append("bytes " + blk.hex())
            # does the mapped VA look like a page table (nonzero, aligned)?
            q = [ctypes.c_uint64.from_address(va + 8 * i).value
                 for i in range(4)]
            lines.append("qwords " + " ".join("%#x" % x for x in q))
    finally:
        if va:
            try:
                g.unmap(va, PAGE)
            except Exception as e:
                lines.append("unmap FAIL %r" % (e,))
        g.close()
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
