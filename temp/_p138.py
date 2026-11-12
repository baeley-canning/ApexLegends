r"""_p138.py -- measure the transform array around a p135 seed: period, bounds, header.

p135 found a live array at 0x5e3429b6c: records carrying `x 0 0 0 | y 0 0 0 | z 0 0 0 | R
| 1 1 1`, duplicated at +0x30000.  0xE0 was only an eyeball estimate, so this probe DERIVES
the period: find every exact `1.0 1.0 1.0` anchor, subtract the 0x34 terminator offset, then
histogram consecutive anchor gaps.  No stride is assumed.

Then: how many records validate (finite translation, one lane > 100), where the array starts
and ends, and what the 0x200 bytes before the first and after the last record hold (count,
base pointer, owner).  The +0x30000 twin is measured the same way as a second copy.
Read-only, gdrv3, 12-try immediate retry.  Writes temp\_p138_out.txt.
Usage: _p138.py [--seed=0x..] [--span=0x2000]
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

OUT = os.path.join(HERE, "_p138_out.txt")
TERM = 0x34
TWIN = 0x30000
F32 = np.dtype("<f4")
SEED = 0x5e3429b6c


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def rd(g, pa, n, secs=4.0):
    box = {}

    def work():
        for k in range(12):
            try:
                box["b"] = g.read_phys(pa, n)
                return
            except OSError as e:
                box["e"] = e
                if k == 5:
                    time.sleep(0.002)

    t = threading.Thread(target=work, daemon=True)
    t.start()
    t.join(secs)
    if t.is_alive():
        return None, "wedge"
    if "b" not in box:
        return None, str(box.get("e"))
    return box["b"], None


def anchors(v):
    """record start offsets for every exact 1.0 1.0 1.0 terminator"""
    one = v == 1.0
    t3 = one[:-2] & one[1:-1] & one[2:]
    return (np.nonzero(t3)[0] + TERM) * 4


def valid(v, off):
    """translation lanes of the record starting at byte offset off"""
    i = off // 4
    if i < 0 or i + 3 > len(v):
        return None
    x, y, z = float(v[i]), float(v[i + 4]), float(v[i + 8])
    for c in (x, y, z):
        if not np.isfinite(c) or abs(c) > 1e6:
            return None
    if max(abs(x), abs(y), abs(z)) < 100:
        return None
    return (x, y, z)


def describe(v, tag):
    a = anchors(v)
    if not len(a):
        say("  %s: no terminator anchors" % tag)
        return None
    gaps = np.diff(a)
    u, c = np.unique(gaps, return_counts=True)
    top = sorted(zip(c, u), reverse=True)[:4]
    say("  %s: anchors=%d gaps(top) %s" % (tag, len(a),
                                           " ".join("%#x x%d" % (g, n) for n, g in top)))
    per = int(top[0][1])
    if per > 0x400:
        per = int(np.median(gaps))
    say("  %s: period=%#x" % (tag, per))
    keep = [o for o in a if valid(v, o)]
    say("  %s: validated=%d/%d  bounds %+#x .. %+#x" % (tag, len(keep), len(a), a[0], a[-1]))
    for o in keep[:40]:
        t = valid(v, o)
        say("    %+#7x %10.2f %10.2f %10.2f" % (o, t[0], t[1], t[2]))
    return per, a[0], a[-1]


def main():
    seed, span = SEED, 0x2000
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
    say("=== p138 array measure %s seed=%#x span=%#x ===" % (time.strftime("%H:%M:%S"), seed, span))
    g = gio.Gio(chunk=0x1000)
    say("ram_top=%#x" % g.ram_top)
    for tag, pa in (("main", seed - span), ("twin", seed + TWIN - span)):
        say("")
        say("### %s @%#x" % (tag, pa))
        b, err = rd(g, pa, 2 * span)
        if not b:
            say("  read failed: %s" % err)
            continue
        v = np.frombuffer(b, F32)
        r = describe(v, tag)
        with open(os.path.join(HERE, "_p138_hex.txt"), "a") as f:
            for row in range(0, len(b), 64):
                f.write("%s %+#7x %s\n" % (tag, row - span,
                                           " ".join("%9.3g" % x for x in v[row // 4:(row + 64) // 4])))
        if not r:
            continue
        per, lo, hi = r
        for what, start, n in (("before", lo - 0x200, 0x200), ("after", hi + per, 0x200)):
            blk, e2 = rd(g, pa + start, n)
            if not blk:
                say("  %s: failed %s" % (what, e2))
                continue
            for row in range(0, n, 64):
                f = np.frombuffer(blk[row:row + 64], F32)
                q = np.frombuffer(blk[row:row + 64], "<u8")
                say("  %s %+#7x %s | %s" % (what, start + row,
                                            " ".join("%9.3g" % x for x in f),
                                            " ".join("%#x" % x for x in q)))
    g.close()
    say("")
    say("RESULT: seed=%#x span=%#x" % (seed, span))
    return 0


if __name__ == "__main__":
    sys.exit(main())
