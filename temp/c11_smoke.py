"""c11: read a handful of known PAs through the driver; report errno each.

Read-only.  Answers: is the transport healthy at all, and is the failure
address-dependent (reserved hole) or global (driver/broken handle)?
"""
import ctypes
import os
import struct
import sys

REPO = os.environ.get("REPO", r"C:\Users\New User\OneDrive\Desktop\cheating")
sys.path.insert(0, os.path.join(REPO, "ext"))
import gio  # noqa: E402

OUT = os.path.join(REPO, "temp", "c11_smoke_out.txt")
L = []
PAS = [0x1000, 0x100000, 0x11000000, 0x11050000, 0x11060000, 0x12000000,
       0x1b25a5000, 0x20000000, 0x27b90000, 0x80000000, 0x100000000]
L.append("elev=%d" % (ctypes.windll.shell32.IsUserAnAdmin() != 0))


def w(s):
    L.append(s)
    print(s)


g = None
try:
    g = gio.Gio()
    w("open ok ram_top=%#x chunk=%#x" % (g.ram_top, g.chunk))
    for pa in PAS:
        for size in (0x1000, 0x10000):
            try:
                d = g.read_phys(pa, size)
                w("  pa=%#x n=%#x OK %r" % (pa, size, d[:8]))
            except OSError as e:
                w("  pa=%#x n=%#x ERR %s" % (pa, size, e))
    # one whole window, page by page, to see the shape of a faulting run
    base = 0x11060000
    good = bad = 0
    for k in range(16):
        try:
            g.read_phys(base + k * 0x1000, 0x1000)
            good += 1
        except OSError:
            bad += 1
    w("window %#x good=%d bad=%d" % (base, good, bad))
except OSError as e:
    w("OPEN ERR %s" % e)
finally:
    if g:
        g.close()
open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")
