"""c49: is the p44d decoy page still alive?  Read it and show its fields."""
import os
import sys

REPO = os.environ.get("REPO", r"C:\Users\New User\OneDrive\Desktop\cheating")
sys.path.insert(0, os.path.join(REPO, "ext"))
import gio  # noqa: E402

OUT = os.path.join(REPO, "temp", "c49_out.txt")
PA = 0x2481D6000
L = []

for base in (PA, 0x62BC6E000, 0x7DE10FB000):
    g = None
    try:
        g = gio.Gio()
        p = g.read_phys(base, 0x1000)
        o = 0xC0
        L.append("page=%#x type@c0=%d pid@290=%#x fl=%#x bl=%#x name=%r"
                 % (base, p[o], int.from_bytes(p[o + 0x1D0:o + 0x1D4], "little"),
                    int.from_bytes(p[o + 0x1D8:o + 0x1E0], "little"),
                    int.from_bytes(p[o + 0x1E0:o + 0x1E8], "little"),
                    p[o + 0x338:o + 0x347]))
    except OSError as e:
        L.append("page=%#x ERR %s" % (base, e))
    finally:
        if g:
            g.close()

open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")
print("\n".join(L))
