"""c45: unit-test shape_at on the svchost page c29 measured."""
import os
import sys

REPO = os.environ.get("REPO", r"C:\Users\New User\OneDrive\Desktop\cheating")
sys.path.insert(0, os.path.join(REPO, "ext"))
import gio  # noqa: E402
import basehunt as bh  # noqa: E402

OUT = os.path.join(REPO, "temp", "c45_out.txt")
PA = 0x15A849000
L = []


def w(s):
    L.append(s)
    print(s)


g = gio.Gio()
try:
    p = g.read_phys(PA, 0x1000)
    w("len=%#x type@80=%d pid@250=%#x fl=%#x bl=%#x name=%r"
      % (len(p), p[0x80], int.from_bytes(p[0x250:0x254], "little"),
         int.from_bytes(p[0x258:0x260], "little"),
         int.from_bytes(p[0x260:0x268], "little"), p[0x3B8:0x3C7]))
    w("phase0x80: %r" % (bh.shape_at(p, 0x80, 0x1D8),))
    w("phase0x00: %r" % (bh.shape_at(p, 0x00, 0x258),))
    for o, pair in ((0x80, 0x1D8), (0x00, 0x258)):
        w("  o=%#x pair=%#x p[o]=%d lane_want=%#x" % (o, pair, p[o], o + pair))
finally:
    g.close()
    open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")
