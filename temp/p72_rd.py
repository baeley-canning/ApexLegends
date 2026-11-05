r"""p72_rd.py -- can the device read the specific frames p72 map choked on?
Read-only, 3 frames, one line each.  No load, no service touch.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio

OUT = os.path.join(HERE, "_p72_rd.txt")
PAS = [0x514c3e000, 0x6c0be0000, 0x6c6af0000]


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
        for pa in PAS:
            try:
                ram = g.is_ram(pa)
            except Exception as e:
                ram = "ram?%r" % e
            try:
                blk = g.read_phys(pa, 0x40)
                q = " ".join("%02x" % b for b in blk[:16])
                lines.append("%#011x ram=%s read=ok %s" % (pa, ram, q))
            except OSError as e:
                lines.append("%#011x ram=%s read=FAIL err=%s %s"
                             % (pa, ram, e.args[0] if e.args else "?",
                                str(e)))
    except Exception:
        import traceback
        lines.append("EXC\n" + traceback.format_exc())
    finally:
        try:
            g.close()
        except Exception:
            pass
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
