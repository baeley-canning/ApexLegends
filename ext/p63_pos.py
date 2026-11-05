r"""p63_pos.py -- find the local player struct by watching which floats move.

No damage needed: you just walk. The name anchor locates the heap cluster; inside
it, the only fields that change smoothly every sample are coordinates. Health is a
small constant int a few bytes away from those coordinates, so once the struct is
found the neighbours are printed as candidates.

Usage: python ext\p63_pos.py --needle=kern30120 [--walk=6] [--out=temp\p63_out.txt]

Read-only: nothing here writes memory.
"""
import os
import struct
import sys
import time

try:
    import winsound
except ImportError:
    winsound = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402
import p56_hits  # noqa: E402

ROOT = os.path.dirname(HERE)
CHUNK = 0x10000
PAGE = gio.PAGE
FULL = (0x400000000, 0x780000000)
CAP = 192


class Out(object):
    def __init__(self, path):
        self.h = open(path, "w", encoding="utf-8")

    def __call__(self, s):
        print(s)
        self.h.write(s + "\n")
        self.h.flush()


def scan(g, lo, hi, needle, out, budget):
    hits = []
    t0 = time.time()
    faults = 0

    def emit(pa, blk):
        nonlocal faults
        if blk is None:
            faults += 1
            return
        i = blk.find(needle)
        while i >= 0:
            hits.append(pa + i)
            i = blk.find(needle, i + 1)

    pa = hi - CHUNK
    while pa >= lo and time.time() - t0 < budget:
        p56_hits.scan_range(g, pa, min(CHUNK, hi - pa), needle, False, emit)
        pa -= CHUNK
    out("SCAN %#x-%#x hits=%d faults=%d secs=%.1f" % (lo, hi, len(hits), faults, time.time() - t0))
    return hits


def densest(hits):
    buckets = {}
    for a in hits:
        buckets[a >> 16] = buckets.get(a >> 16, 0) + 1
    if not buckets:
        return hits, 0
    best = max(buckets, key=lambda k: buckets[k])
    near = [a for a in hits if abs((a >> 16) - best) <= 1]
    return (near, best) if len(near) >= 3 else (hits, best)


def pages_near(hits, reach=2):
    out, seen = [], set()
    for a in hits:
        p = a & ~0xFFF
        for k in range(-reach, reach + 1):
            q = p + k * PAGE
            if q not in seen and q >= PAGE:
                seen.add(q)
                out.append(q)
    return out[:CAP]


def shot(g, pages):
    vals = {}
    for p in pages:
        try:
            buf = g.read_phys(p, PAGE)
        except OSError:
            continue
        for i in range(0, PAGE - 3, 4):
            v = struct.unpack_from("<I", buf, i)[0]
            if v:
                vals[p + i] = v
    return vals


def as_float(v):
    f = struct.unpack("<f", struct.pack("<I", v))[0]
    if f != f or f in (float("inf"), float("-inf")):
        return None
    if 0.05 < abs(f) < 200000.0:
        return f
    return None


def main(argv):
    needle, walk, out_path = None, 6.0, os.path.join(ROOT, "temp", "p63_out.txt")
    last = os.path.join(ROOT, "temp", "p60_name_u16.txt")
    for a in argv:
        if a.startswith("--needle="):
            needle = a[9:]
        elif a.startswith("--walk="):
            walk = float(a[7:])
        elif a.startswith("--last="):
            last = a[7:]
        elif a.startswith("--out="):
            out_path = a[6:]
    if not needle:
        print("usage: p63_pos.py --needle=text [--walk=s] [--last=hitsfile] [--out=path]")
        return 2
    nb = needle.encode()

    out = Out(out_path)
    out("# p63_pos %s needle=%r" % (time.strftime("%Y-%m-%d %H:%M:%S"), nb))
    g = gio.Gio()
    hits = []
    if os.path.exists(last):
        with open(last, "r", encoding="utf-8", errors="replace") as f:
            pg = [int(l.split("addr=")[1], 16) for l in f if l.startswith("HIT ")]
        if pg:
            lo = max(FULL[0], min(pg) - 0x1000000)
            hi = min(FULL[1], max(pg) + 0x1000000)
            if hi - lo <= 0x30000000:
                hits = scan(g, lo, hi, nb, out, 25.0)
    if not hits:
        hits = scan(g, FULL[0], FULL[1], nb, out, 90.0)
    if not hits:
        out("VERDICT no-anchor")
        return 1
    hits, centre = densest(hits)
    out("ANCHOR hits=%d cluster=%#011x" % (len(hits), centre << 16))

    pages = pages_near(hits)
    out("WATCH pages=%d -- move now, keep walking" % len(pages))
    if winsound:
        for _ in range(3):
            try:
                winsound.Beep(1100, 200)
            except RuntimeError:
                pass
    shots = []
    for _ in range(8):
        shots.append(shot(g, pages))
        time.sleep(walk / 8.0)
    if winsound:
        try:
            winsound.Beep(700, 400)
        except RuntimeError:
            pass
    out("shots done")

    pos = {}
    for addr in shots[0]:
        seq = [s.get(addr) for s in shots]
        if any(v is None for v in seq):
            continue
        fl = [as_float(v) for v in seq]
        if any(f is None for f in fl):
            continue
        steps = [abs(fl[i] - fl[i - 1]) for i in range(1, len(fl))]
        if min(steps) <= 1e-4 or max(steps) > 5000.0:
            continue
        pos[addr] = fl
    out("MOVING floats=%d" % len(pos))

    addrs = sorted(pos)
    groups, cur = [], []
    for a in addrs:
        if cur and a - cur[-1] > 0x80:
            groups.append(cur)
            cur = []
        cur.append(a)
    if cur:
        groups.append(cur)
    out("GROUPS %d" % len(groups))

    def constant(addr):
        seq = [s.get(addr) for s in shots]
        return seq[0] if all(v == seq[0] for v in seq) else None

    for gi, grp in enumerate(groups[:12]):
        out("GROUP %d at %#011x nfloat=%d" % (gi, grp[0], len(grp)))
        for a in grp[:4]:
            out("  pos %#011x %s" % (a, ",".join("%.2f" % f for f in pos[a])))
        found = 0
        for a in range(grp[0] - 0x600, grp[-1] + 0x600, 4):
            v = constant(a)
            if v is not None and 1 <= v <= 300:
                out("  const %#011x int=%d" % (a, v))
                found += 1
                if found >= 12:
                    break
    out("VERDICT done groups=%d" % len(groups))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
