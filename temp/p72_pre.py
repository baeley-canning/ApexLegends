r"""p72_pre.py -- R3 pre-state for the p72 run: are the p71 bases still live?

Reads only.  Both settled bases (0x6c6af0864 health / 0x6607b9f78 twin) get
is_ram plus a float read at every confirmed offset, so a stale page is visible
before p72 dumps 64 MiB of .data at it.  Values are measured, never assumed:
the session is 70 min old and Apex recycles pages.

Usage: python temp\p72_pre.py
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
os.environ.setdefault("DUMP_OUT", "p72_pre_out.txt")
os.environ.setdefault("DUMP_PROG", "p72_pre_prog.txt")
import gio  # noqa: E402
import dumplive as dl  # noqa: E402

OUT = os.path.join(HERE, "p72_pre_out.txt")
dl.OUT = OUT
dl.PROG = os.path.join(HERE, "p72_pre_prog.txt")

BASES = (0x6C6AF0864, 0x6607B9F78)
OFFS = (0x0, 0x4, 0x28, 0x40, 0x50, 0x78, 0xD8 + 0x28, 0xD8 + 0x40)
LEN = 0x140                     # 0x118 max offset + 4, reads stay inside one page


def f(u):
    v = struct.unpack("<f", u)[0]
    return "nan" if v != v else "%g" % v


def body():
    log = dl.log
    live = 0
    g = gio.Gio()
    try:
        for pa in BASES:
            log("PRE %#x page_ram=%s" % (pa, g.is_ram(pa)))
            page = pa & ~0xFFF
            off = pa - page
            try:
                blk = g.read_phys_checked(page, off + LEN)
            except OSError as e:
                log("  read fault: %s" % e)
                continue
            if len(blk) < off + LEN:
                log("  short read %#x" % len(blk))
                continue
            vals = "  ".join("%#x:%s" % (o, f(blk[off + o:off + o + 4]))
                             for o in OFFS)
            log("  " + vals)
            # health in 0..100 and the 0x50 max still exactly 100 = same struct
            h = struct.unpack("<f", blk[off:off + 4])[0]
            m = struct.unpack("<f", blk[off + 0x50:off + 0x54])[0]
            if 0.0 <= h <= 100.0 and m == 100.0:
                live += 1
    finally:
        g.close()
    log("LIVE %d/%d" % (live, len(BASES)))
    log("VERDICT: PRE_STATE_%s" % ("LIVE" if live else "STALE"))


def main():
    if dl.elevation() != 1 and "--elevated" not in sys.argv:
        try:
            os.remove(OUT)
        except OSError:
            pass
        msg = dl.run_elevated(subprocess_line())
        if not os.path.exists(OUT):
            print("elevation returned %r, no output" % msg)
            return 3
        print(open(OUT, encoding="utf-8").read())
        return 0
    try:
        body()
    except Exception:
        import traceback
        dl.log("EXC " + traceback.format_exc().replace("\n", " | "))
    open(OUT, "w", encoding="utf-8").write("\n".join(dl.LOG) + "\n")
    return 0


def subprocess_line():
    import subprocess
    return subprocess.list2cmdline([sys.executable, os.path.abspath(__file__),
                                    "--elevated"])


if __name__ == "__main__":
    sys.exit(main())
