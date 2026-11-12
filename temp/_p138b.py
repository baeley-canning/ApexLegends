r"""_p138b.py -- bounds and header of the 0x1C0 transform array around a p134 seed.

p138 measured wrong (units bug + un-deduped anchors).  The hex dump settles the layout: a
record is `(x,0,0,0)(y,0,0,0)(z,0,0,0)(w,1,1,1)` + a 4x4 rotation, period 0x1C0, marker row
repeating at -0x1e80/-0x1cc0/-0x1b00 from the seed.  This probe takes that period as a
HYPOTHESIS and validates it: marker = exact 1.0 1.0 1.0 at start+0x34 with a finite start+0x30,
gaps between accepted markers must equal 0x1C0, walk outward until a record fails, and then
dump 0x200 bytes before the first and after the last record - that is where the count, the
base pointer and the owner live.
Read-only, gdrv3, 12-try immediate retry.  Writes temp\_p138b_out.txt.
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

OUT = os.path.join(HERE, "_p138b_out.txt")
PER = 0x1C0
TERM = 0x34
TWIN = 0x30000
SPAN = 0x8000
MAXR = 160
F32 = np.dtype("<f4")
SEED = 0x5e3429b6c


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


def ok_rec(v, i):
    """FULL marker at float index i: (x,0,0,0)(y,0,0,0)(z,0,0,0)(w,1,1,1).

    The short form `(x,0,0,0)(w,1,1,1)(1,nan,..)` also exists and sits at irregular offsets,
    so it must not count: requiring the three zero lanes of each row leaves only the real
    record heads.
    """
    if i < 0 or i + 16 > len(v):
        return False
    for z in (1, 2, 3, 5, 6, 7, 9, 10, 11):
        if v[i + z] != 0.0:
            return False
    w = float(v[i + 12])
    if not np.isfinite(w) or abs(w) > 1e7:
        return False
    return bool(v[i + 13] == 1.0 and v[i + 14] == 1.0 and v[i + 15] == 1.0)


def report(tag, v, origin, seed_off):
    hits = []
    i = 0
    while i < len(v) - 20:
        if ok_rec(v, i):
            hits.append(i)
            i += 0x40 // 4
        else:
            i += 1
    if len(hits) < 3:
        say("  %s: only %d marker rows in %#x" % (tag, len(hits), len(v) * 4))
        return None
    d = np.diff(hits) * 4
    u, c = np.unique(d, return_counts=True)
    top = sorted(zip(c, u), reverse=True)[:3]
    say("  %s: marker rows=%d gaps %s" % (tag, len(hits),
                                          " ".join("%#x x%d" % (g, n) for n, g in top)))
    per = int(top[0][1]) if top[0][1] <= 0x800 else PER
    # longest chain on the modal gap
    best, cur = [], [hits[0]]
    for a, b in zip(hits, hits[1:]):
        if (b - a) * 4 == per:
            cur.append(b)
        else:
            if len(cur) > len(best):
                best = cur
            cur = [b]
    if len(cur) > len(best):
        best = cur
    if len(best) < 3:
        say("  %s: no chain on period %#x" % (tag, per))
        return None
    say("  %s: chain=%d period=%#x  %+#x .. %+#x  (nearest %+#x from seed)"
        % (tag, len(best), per, best[0] * 4, best[-1] * 4,
           min((i * 4 - seed_off for i in best), key=abs)))
    for i in best[:34]:
        say("    %+#7x %11.2f %11.2f %11.2f %11.2f"
            % (i * 4, v[i], v[i + 4], v[i + 8], v[i + 12]))
    return best[0] * 4, best[-1] * 4, per


def main():
    seed = SEED
    for a in sys.argv:
        if a.startswith("--seed="):
            seed = int(a.split("=", 1)[1], 0)
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" --seed=%#x' % (os.path.abspath(__file__), seed)))
        return 0
    open(OUT, "w").close()
    say("=== p138b array bounds %s seed=%#x per=%#x span=%#x ==="
        % (time.strftime("%H:%M:%S"), seed, PER, SPAN))
    g = gio.Gio(chunk=0x1000)
    base = (seed - SPAN) & ~0xFFF
    seed_off = seed - base
    say("ram_top=%#x base=%#x seed_off=%#x" % (g.ram_top, base, seed_off))
    for tag, b0 in (("main", base), ("twin", base + TWIN)):
        say("")
        say("### %s @%#x" % (tag, b0))
        b, err = rd(g, b0, SPAN * 2)
        if not b:
            say("  read failed: %s" % err)
            continue
        v = np.frombuffer(b, F32)
        r = report(tag, v, b0, seed_off)
        if not r:
            continue
        first, last, per = r
        for what, start in (("before", first - 0x200), ("after", last + per)):
            blk, e2 = rd(g, b0 + start - 0x1000, 0x1200)
            if not blk:
                say("  %s: failed %s" % (what, e2))
                continue
            vv = np.frombuffer(blk, F32)
            qq = np.frombuffer(blk, "<u8")
            for row in range(0x1000 - 0x40, 0x1000 + 0x200, 64):
                say("  %s %+#7x %s | %s"
                    % (what, start - 0x1000 + row,
                       " ".join("%9.3g" % x for x in vv[row // 4:(row + 64) // 4]),
                       " ".join("%#x" % x for x in qq[row // 8:(row + 64) // 8])))
    g.close()
    say("")
    say("RESULT: seed=%#x per=%#x" % (seed, PER))
    return 0


if __name__ == "__main__":
    sys.exit(main())
