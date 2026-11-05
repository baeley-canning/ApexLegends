r"""p72_kmap.py -- two last routes to the dead DTB frame + does the driver's own
RAM map even contain it.  Read-only.
"""
import ctypes
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio
import dumplive as dl

OUT = os.path.join(HERE, "_p72_kmap.txt")
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
    buf = gio.alloc_locked(PAGE)
    try:
        # 1) MAP_K with the caller buffer: different mapping call than READ
        ok, err, kva = g.map_kernel(PA, PAGE, buf)
        lines.append("map_kernel ok=%s err=%r kva=%r" % (ok, err, kva))
        if ok and kva:
            need = []
            lines.append("kernel bytes " + ctypes.string_at(buf, 16).hex())
            try:
                lines.append("kva bytes " + ctypes.string_at(kva, 16).hex())
            except Exception as e:
                need.append("kva unreadable %r" % (e,))
            lines += need

        # 2) straight READ again, twice, to see determinism once more
        for i in range(2):
            try:
                lines.append("read try%d ok %s" % (i, g.read_phys(PA, 8).hex()))
            except Exception as e:
                lines.append("read try%d FAIL %r" % (i, e))

        # 3) is the PA inside the driver-reported RAM map at all?
        good, note = dl.ram_map()
        lines.append("ram_map %s entries=%d" % (note, len(good)))
        near = [(a, b) for a, b in good if abs(a - PA) < 0x2000000
                or abs(b - PA) < 0x2000000]
        for a, b in near:
            inside = a <= PA < b
            lines.append("  range %#x-%#x inside=%s" % (a, b, inside))
        lines.append("inside_any=%s"
                     % any(a <= PA < b for a, b in good))
    finally:
        try:
            gio.kernel32.VirtualFree(buf, 0, gio.MEM_RELEASE)
        except Exception:
            pass
        g.close()
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
