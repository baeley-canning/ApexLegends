r"""_p140.py -- find and measure the entity-record chain around a p135 seed.

The p135 grid of seed 0x5c3230c5c shows the shape: each record is `(x, r, r, 0)(y, 0, 0, s)
(z, 1, 1, 1)` - a 4x4 root transform with the translation in lane 0 of each row - and the same
triple is repeated 0x30 bytes later (+-0.2%), which validates a hit without any guesswork.
0x100 bytes of other fields follow the terminator.

This probe: scan a window around the seed for that pattern, chain the hits, report the gap
distribution (the real record stride), the chain bounds and count, then dump the 0x100 bytes
after each of the first records - that is where hp / shield / team live.
Read-only, gdrv3, 12-try immediate retry.  Writes temp\_p140_out.txt.
Usage: _p140.py [--seed=0x..] [--span=0x4000]
"""
import os
import sys
import threading
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import gio
import dumplive as dl

OUT = os.path.join(HERE, "_p140_out.txt")
F32 = np.dtype("<f4")
SEED = 0x5c3230c5c
NEAR = 0.002


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def rd(g, pa, n, secs=5.0):
    box = {}

    def work():
        for k in range(12):
            try:
                box["b"] = g.read_phys(pa, n)
                return
            except OSError as e:
                box["e"] = repr(e)
                if k == 5:
                    time.sleep(0.002)

    t = threading.Thread(target=work, daemon=True)
    t.start()
    t.join(secs)
    if t.is_alive():
        return None, "wedge"
    if "b" not in box:
        return None, box.get("e", "no-attempt")
    return box["b"], None


def near(a, b):
    return abs(a - b) <= max(2.0, NEAR * max(abs(a), abs(b)))


def root(v, i):
    """root transform at float index i, self-validated by its +0x30 duplicate.

    Layout (measured in temp\\_p135_hex_5c3230c5c.txt):
      +0x00 (x,r,r,0)  +0x10 (y,0,0,s)  +0x20 (z,?,?,0)
      +0x30 (x,r,r,0)  +0x40 (y,0,0,s)  +0x50 (z,1,1,1)
    so the terminator is at +0x50 and the z of the two copies may differ by ~2 units.
    """
    if i < 0 or i + 24 > len(v):
        return False
    if not (v[i + 21] == 1.0 and v[i + 22] == 1.0 and v[i + 23] == 1.0):
        return False
    if v[i + 3] != 0.0 or v[i + 5] != 0.0 or v[i + 6] != 0.0:
        return False
    x, y, z = float(v[i]), float(v[i + 4]), float(v[i + 8])
    if not (np.isfinite(x) and np.isfinite(y) and np.isfinite(z)):
        return False
    d = 0x30 // 4
    if not (near(x, v[i + d]) and near(y, v[i + 4 + d]) and near(z, v[i + 8 + d])):
        return False
    return abs(x) > 250 or abs(z) > 250


def main():
    seed, span = SEED, 0x4000
    for a in sys.argv:
        if a.startswith("--seed="):
            seed = int(a.split("=", 1)[1], 0)
        elif a.startswith("--span="):
            span = int(a.split("=", 1)[1], 0)
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" --seed=%#x --span=%#x' % (os.path.abspath(__file__), seed, span)))
        return 0
    open(OUT, "w").close()
    say("=== p140 record chain %s seed=%#x span=%#x ===" % (time.strftime("%H:%M:%S"), seed, span))
    g = gio.Gio(chunk=0x1000)
    base = (seed - span) & ~0xFFF
    b, err = rd(g, base, span * 2)
    if not b:
        say("read failed: %s" % err)
        return 1
    v = np.frombuffer(b, F32)
    hits = []
    i = 0
    while i < len(v) - 40:
        if root(v, i):
            hits.append(i)
            i += 0x20 // 4
        else:
            i += 1
    say("base=%#x seed_off=%#x roots=%d" % (base, seed - base, len(hits)))
    if len(hits) < 2:
        say("RESULT: roots=%d" % len(hits))
        say("VERDICT: FAIL - pattern not found here")
        return 1
    gaps = np.diff(hits) * 4
    u, c = np.unique(gaps, return_counts=True)
    say("gaps: %s" % " ".join("%#x x%d" % (gv, n) for n, gv in sorted(zip(c, u), reverse=True)[:6]))
    say("chain %+#x .. %+#x  first=%+#x from seed"
        % (hits[0] * 4, hits[-1] * 4, hits[0] * 4 - (seed - base)))
    for i in hits[:24]:
        say("  ROOT %+#7x %11.2f %11.2f %11.2f" % (i * 4, v[i], v[i + 4], v[i + 8]))
    say("-- 0x100 after the first 6 terminators (float lanes + qwords) --")
    for i in hits[:6]:
        st = i * 4 + 0x40
        blk, e2 = rd(g, base + st, 0x100)
        if not blk:
            say("  %+#7x failed %s" % (st, e2))
            continue
        fv = np.frombuffer(blk, F32)
        qv = np.frombuffer(blk, "<u8")
        for row in range(0, 0x100, 64):
            say("  %+#7x %s | %s" % (st + row,
                                      " ".join("%9.3g" % x for x in fv[row // 4:(row + 64) // 4]),
                                      " ".join("%#x" % x for x in qv[row // 8:(row + 64) // 8])))
    g.close()
    say("RESULT: seed=%#x roots=%d" % (seed, len(hits)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
