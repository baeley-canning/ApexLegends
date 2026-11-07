r"""qk_vp.py -- pick the view-projection out of the five live matrices, and cache
image_pa + vp_rva for the producer.

Both halves are already proven separately: qk_image finds the image physically and
lists the matrix family at image+0xDB5BC40..0xDB5BFC0; qk_esp finds entity
positions by name.  This projects each entity through each matrix (in both
conventions) and keeps the matrix that puts them on screen - that is the VP.

Usage: qk_vp.py [--local=kern30120] [--out=FILE]
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gio             # noqa: E402
import dumplive as dl   # noqa: E402
import qk_esp as E     # noqa: E402
import qk_image as I    # noqa: E402
import qk_phys as P     # noqa: E402

ROOT = os.path.dirname(HERE)
TMP = os.path.join(ROOT, "temp")
RVAS = (0x0DB5BC40, 0x0DB5BD20, 0x0DB5BE00, 0x0DB5BEE0, 0x0DB5BFC0)
OUT = None
LOG = []


def out(s):
    line = str(s).encode("ascii", "replace").decode("ascii")
    print(line)
    LOG.append(line)
    if OUT:
        with open(OUT, "a", encoding="utf-8") as f:
            f.write(line + "\n")


def arg(name, default=None, cast=str):
    for i, a in enumerate(sys.argv):
        if a == "--" + name and i + 1 < len(sys.argv):
            return cast(sys.argv[i + 1])
        if a.startswith("--" + name + "="):
            return cast(a.split("=", 1)[1])
    return default


def find_image(g, ranges):
    for rlo, rhi in ranges:
        pa = (rlo + 7) & ~7
        while pa + 0x10000 <= rhi:
            try:
                blk = dl.retry_phys(g, pa, 0x10000, tries=1)
            except OSError:
                pa += 0x10000
                continue
            i = blk.find(b"MZ")
            while i >= 0:
                r = I.check_image(g, pa + i)
                if r:
                    return pa + i, r
                i = blk.find(b"MZ", i + 1)
            pa += 0x10000
    return None, None


def main():
    global OUT
    OUT = os.path.abspath(arg("out", os.path.join(TMP, "qk_vp_%d.txt" % os.getpid())))
    open(OUT, "w").close()
    if not dl.elevation() and ("--no-elevate" not in sys.argv):
        cmd = " ".join('"%s"' % a if " " in a else a for a in sys.argv) + " --no-elevate"
        print(dl.run_elevated(cmd))
        return 0
    needle = arg("local", "kern30120")
    out("===== qk_vp: identify the view-projection =====")
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        out("gio: %s" % e)
        return 2
    try:
        ranges, note = dl.usable_ranges(g.ram_top, None, None)
        out("ranges=%d (%s)" % (len(ranges), note))
        pa, meta = find_image(g, ranges)
        if not pa:
            out("RESULT: no-image (game not running?)")
            return 8
        out("image_pa=%#x stamp=%#x" % (pa, meta[2]))
        ents = E.find_entities(g, ranges, needle)
        out("entity positions: %d" % len(ents))
        pts = [(e[1], e[2], e[3]) for e in ents[:40]]
        if not pts:
            out("RESULT: no-entities to project")
            return 8
        best = None
        for rva in RVAS:
            try:
                b = dl.retry_phys(g, pa + rva, 64, tries=2)
            except OSError:
                out("  rva %#010x read fault" % rva)
                continue
            m = struct.unpack("<16f", b)
            ok = 0
            for (x, y, z) in pts:
                if P.project(m, x, y, z, 1920, 1080):
                    ok += 1
            out("  rva %#010x on-screen=%d/%d" % (rva, ok, len(pts)))
            if ok and (best is None or ok > best[1]):
                best = (rva, ok, m)
        if not best:
            out("RESULT: no-matrix-projects")
            out("VERDICT: PARTIAL - none of the five landed an entity on screen")
            return 8
        out("RESULT: vp_rva=%#x (on-screen %d/%d) image_pa=%#x"
            % (best[0], best[1], len(pts), pa))
        out("VERDICT: PASS - VP identified; producer can read image_pa+%#x" % best[0])
        with open(os.path.join(TMP, "qk_offsets.txt"), "w") as f:
            f.write("image_pa=0x%X\nvp_rva=0x%X\n" % (pa, best[0]))
        out("cached temp\\qk_offsets.txt")
        return 0
    finally:
        try:
            g.close()
        except Exception:                        # noqa: BLE001
            pass


if __name__ == "__main__":
    sys.exit(main())
