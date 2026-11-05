"""paprobe4.py -- current link bytes of the three decoy blocks.

p43x saw a KVA at +0x1d8 and p43z then looked at +0x258 (zero).  Before any
base search, read both candidate lanes of all three blocks: a real LIST_ENTRY
shows two KVAs 8 bytes apart whose low 12 bits differ by 8 (lane and lane+8).
READ-ONLY.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

OUT = os.path.join(os.path.dirname(HERE), "_ritual", "p44d_link.txt")
BASES = [0x2481D60C0, 0x62BC6E190, 0x7DE10FBF0]
LOG = []


def log(s):
    LOG.append(s)
    print(s)


g = gio.Gio(chunk=0x10000)
for base in BASES:
    try:
        p = g.read_phys(base & ~0xFFF, 0x2000)
    except OSError as e:
        log("base=%#x ERR %s" % (base, e))
        continue
    b = base & 0xFFF
    log("base=%#x type=%d pid=%#x" % (base, p[b],
                                      struct.unpack_from("<I", p, b + 0x1D0)[0]))
    for off in (0x1C8, 0x1D8, 0x1E0, 0x1E8, 0x250, 0x258, 0x260, 0x268):
        v = struct.unpack_from("<Q", p, b + off)[0]
        log("   +%#05x %016x%s" % (off, v,
                                   "  <kva" if (v >> 48) == 0xFFFF else ""))
g.close()
open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
print("VERDICT: PAPROBE4_DONE")
