r"""_p141.py -- array base, count and owner of the 0xE0 root array.

p140 validated the record shape (self-validated transform, 0xE0 stride, 65 roots in 0x7000).
Before this can feed an ESP the array's real base and total length must be known, plus
whatever object points at it.  Walk backward and forward from the earliest/latest known root in
0xE0 steps, count consecutive failures (stop at 8), then dump the 0x200 bytes before the base -
a std::vector lives there as {begin, end, capacity} if the array is heap-owned.
Read-only, gdrv3, 12-try immediate retry.  Writes temp\_p141_out.txt.
Usage: _p141.py [--at=0x..]  (a known root, chain is re-derived the same way p140 does)
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

OUT = os.path.join(HERE, "_p141_out.txt")
F32 = np.dtype("<f4")
PER = 0xE0
AT = 0x5c322c10c
NEAR = 0.002
MAXFAIL = 8


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


def root_at(g, pa):
    b, err = rd(g, pa, 0x60)
    if not b:
        return None, err
    v = np.frombuffer(b, F32)
    if not (v[21] == 1.0 and v[22] == 1.0 and v[23] == 1.0):
        return None, "no-term"
    if v[3] != 0.0 or v[5] != 0.0 or v[6] != 0.0:
        return None, "no-zero-lanes"
    x, y, z = float(v[0]), float(v[4]), float(v[8])
    if not (np.isfinite(x) and np.isfinite(y) and np.isfinite(z)):
        return None, "nan"
    if not (near(x, v[12]) and near(y, v[16]) and near(z, v[20])):
        return None, "no-dup"
    if abs(x) < 250 and abs(z) < 250:
        return None, "world-bounds"
    return (x, y, z), None


def walk(g, start, step):
    got, miss = [], 0
    pa = start
    while miss < MAXFAIL and abs(pa - start) < 0x40000:
        pa += step
        t, _e = root_at(g, pa)
        if t:
            got.append((pa, t))
            miss = 0
        else:
            miss += 1
    return got


def main():
    at = AT
    for a in sys.argv:
        if a.startswith("--at="):
            at = int(a.split("=", 1)[1], 0)
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" --at=%#x' % (os.path.abspath(__file__), at)))
        return 0
    open(OUT, "w").close()
    say("=== p141 array base %s at=%#x ===" % (time.strftime("%H:%M:%S"), at))
    g = gio.Gio(chunk=0x1000)
    t0, e0 = root_at(g, at)
    say("at: %s %s" % (t0, e0))
    if not t0:
        g.close()
        return 1
    span = 0x40000
    base = (at - span // 2) & ~0xFFF
    b, err = rd(g, base, span)
    if not b:
        say("scan read failed: %s" % err)
        g.close()
        return 1
    v = np.frombuffer(b, F32)
    hits, i = [], 0
    while i < len(v) - 24:
        if root_at_buf(v, i):
            hits.append(i * 4)
            i += 0x20 // 4
        else:
            i += 1
    say("base=%#x hits=%d at_off=%#x" % (base, len(hits), at - base))
    if len(hits) < 4:
        say("RESULT: hits=%d" % len(hits))
        say("VERDICT: FAIL - too few roots for bounds")
        g.close()
        return 1
    per_page = {}
    for h in hits:
        per_page[h // 0x1000] = per_page.get(h // 0x1000, 0) + 1
    dense = sorted(per_page.items())
    say("density per 4K page (offset:count): %s"
        % " ".join("%#x:%d" % (p * 0x1000, n) for p, n in dense))
    say("bounds %+#x .. %+#x" % (hits[0], hits[-1]))
    for what, start, n in (("pre-base", hits[0] - 0x200, 0x200),
                           ("post-end", hits[-1] + PER, 0x100)):
        blk, e2 = rd(g, base + start, n)
        if not blk:
            say("%s failed %s" % (what, e2))
            continue
        fv = np.frombuffer(blk, F32)
        qv = np.frombuffer(blk, "<u8")
        say("-- %s --" % what)
        for row in range(0, n, 64):
            say("  %+#7x %s | %s" % (start + row,
                                      " ".join("%9.3g" % x for x in fv[row // 4:(row + 64) // 4]),
                                      " ".join("%#x" % x for x in qv[row // 8:(row + 64) // 8])))
    g.close()
    say("RESULT: base=%#x hits=%d" % (base, len(hits)))
    return 0


def root_at_buf(v, i):
    if i < 0 or i + 24 > len(v):
        return False
    if not (v[i + 21] == 1.0 and v[i + 22] == 1.0 and v[i + 23] == 1.0):
        return False
    if v[i + 3] != 0.0 or v[i + 5] != 0.0 or v[i + 6] != 0.0:
        return False
    x, y, z = float(v[i]), float(v[i + 4]), float(v[i + 8])
    if not (np.isfinite(x) and np.isfinite(y) and np.isfinite(z)):
        return False
    return near(x, v[i + 12]) and near(y, v[i + 16]) and near(z, v[i + 20]) \
        and (abs(x) > 250 or abs(z) > 250)


if __name__ == "__main__":
    sys.exit(main())
