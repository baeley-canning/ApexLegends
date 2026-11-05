r"""p61_live.py -- one-shot live coordinator: anchor, snapshot, damage window, diff.

Single elevated process, one device handle, so no per-step relaunch cost.

Usage: python ext\p61_live.py --needle=kern30120 [--pre=6] [--post=8]
       [--last=temp\p60_name_u16.txt] [--win=MiB] [--pages=N] [--loose]
       [--out=path]        (default temp\p61_<timestamp>.txt, never shared)

Sequence: narrow rescan around the previous match's anchor cluster (falls back to
the full band only if the window is cold) -> pre-snapshot of the hit pages ->
countdown -> post-snapshot at +pre and +pre+post -> diff.

A candidate field must drop across the damage and stay flat afterwards, which is
what a health/shield subtract does and what position churn does not.
Read-only: nothing here writes memory.
"""
import os
import struct
import sys
import time

try:
    import winsound
except ImportError:                     # non-Windows fallback
    winsound = None


def beep(freq, ms):
    """Audible cue -- the player is in the game, console text is invisible."""
    if winsound:
        try:
            winsound.Beep(freq, ms)
        except RuntimeError:
            pass

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402
import p56_hits  # noqa: E402

ROOT = os.path.dirname(HERE)
CHUNK = 0x10000
PAGE = gio.PAGE
FULL = (0x400000000, 0x780000000)
SPAN = 0x1000000      # +-16 MiB around the remembered cluster
CAP = 512             # pages snapshotted per shot (densest cluster is ~0x30000 wide)
PAGES = 2             # +-pages around each hit (--pages=N to widen)
LOOSE = False         # accept a 1-point drop instead of 3
SPANW = 0             # >0: snapshot this many MiB contiguous around the hits
SHOTS = 8             # post-snapshot count
EVERY = 1.5           # seconds between shots


class Out(object):
    def __init__(self, path):
        self.h = open(path, "w", encoding="utf-8")

    def __call__(self, s):
        print(s)
        self.h.write(s + "\n")
        self.h.flush()

    def close(self):
        self.h.close()


def window_from_last(path):
    pages = []
    if not path or not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("HIT "):
                pages.append(int(line.split("addr=")[1], 16) & ~0xFFF)
    if not pages:
        return None
    lo, hi = min(pages) - SPAN, max(pages) + SPAN
    if hi - lo > 0x30000000:
        return None
    return max(FULL[0], lo), min(FULL[1], hi)


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
    """Return hits around the tightest 64 KiB cluster -- UI copies are spread out,
    the entity struct is not."""
    buckets = {}
    for a in hits:
        k = a >> 16
        buckets[k] = buckets.get(k, 0) + 1
    if not buckets:
        return hits, 0
    best = max(buckets, key=lambda k: buckets[k])
    near = [a for a in hits if abs((a >> 16) - best) <= 1]
    return (near, best) if len(near) >= 3 else (hits, best)


def snap(g, hits):
    if SPANW:
        half = SPANW << 19                     # half the span, bytes
        lo = (min(hits) & ~0xFFF) - half
        hi = (max(hits) & ~0xFFF) + half
        pages = list(range(max(lo, PAGE), hi + 1, PAGE))
    else:
        pages, seen = [], set()
        for a in hits:
            p = a & ~0xFFF
            for k in range(-PAGES, PAGES + 1):
                q = p + k * PAGE
                if q not in seen and q >= PAGE:
                    seen.add(q)
                    pages.append(q)
        pages.sort()
    vals = {}
    cap = len(pages) if SPANW else CAP
    for p in pages[:cap]:
        try:
            buf = g.read_phys(p, PAGE)
        except OSError:
            continue
        for i in range(0, PAGE - 3, 4):
            v = struct.unpack_from("<I", buf, i)[0]
            if v:
                vals[p + i] = v
    return vals


def main(argv):
    needle, pre, post = None, 12.0, 8.0
    out_path = os.path.join(ROOT, "temp", "p61_%s.txt" % time.strftime("%Y%m%d_%H%M%S"))
    last = os.path.join(ROOT, "temp", "p60_name_u16.txt")
    wait = 0.0
    for a in argv:
        if a.startswith("--needle="):
            needle = a[9:]
        elif a.startswith("--wait="):
            wait = float(a[7:])
        elif a.startswith("--pre="):
            pre = float(a[6:])
        elif a.startswith("--post="):
            post = float(a[7:])
        elif a.startswith("--last="):
            last = a[7:]
        elif a.startswith("--out="):
            out_path = a[6:]
        elif a.startswith("--win="):        # forced window in MiB either side
            globals()["SPAN"] = int(a[6:]) << 20
        elif a.startswith("--pages="):      # +-pages around each anchor hit
            globals()["PAGES"] = int(a[8:])
        elif a == "--loose":                # accept a 1-point drop
            globals()["LOOSE"] = True
        elif a.startswith("--spanw="):      # contiguous MiB band around the hits
            globals()["SPANW"] = int(a[8:])
        elif a.startswith("--shots="):
            globals()["SHOTS"] = int(a[8:])
        elif a.startswith("--every="):
            globals()["EVERY"] = float(a[8:])
    if not needle:
        print("usage: p61_live.py --needle=text [--wait=s] [--pre=8] [--post=8] [--last=hitsfile] [--out=path]")
        return 2
    nb = needle.encode()

    out = Out(out_path)
    out("# p61_live %s needle=%r" % (time.strftime("%Y-%m-%d %H:%M:%S"), nb))
    g = gio.Gio()
    try:
        win = window_from_last(last)
        hits = []
        if win:
            out("window=%#x-%#x (from %s)" % (win[0], win[1], os.path.basename(last or "")))
            hits = scan(g, win[0], win[1], nb, out, 25.0)
            if len(hits) < 25:
                out("window weak (%d) -> full band too" % len(hits))
                hits += scan(g, FULL[0], FULL[1], nb, out, 90.0)
        if not hits:
            out("window cold -> full band")
            hits = scan(g, FULL[0], FULL[1], nb, out, 90.0)
        if not hits:
            out("VERDICT no-anchor")
            return 3
        hits = sorted(set(hits))
        hits, centre = densest(hits)
        out("ANCHOR hits=%d cluster=%#011x first=%#x" % (len(hits), centre << 16, hits[0]))
        try:
            open(os.path.join(ROOT, "temp", "p61_cluster.txt"), "w").write(
                "%#x %s\n" % (centre << 16, needle))
        except OSError:
            pass

        if wait > 0:
            out("READY wait=%.0fs (land, then get to a safe spot)" % wait)
            time.sleep(wait)
        a0 = snap(g, hits)
        out("PRE values=%d" % len(a0))
        for t in range(int(pre), 0, -1):
            out("NADE NOW %d" % t)
            beep(880, 120)
            time.sleep(1.0)
        beep(1400, 500)
        beep(1400, 500)
        beep(1400, 500)
        out("GO")
        shots = [a0]
        for i in range(1, SHOTS):
            time.sleep(EVERY)
            shots.append(snap(g, hits))
            out("shot %d values=%d" % (i, len(shots[-1])))

        n = len(shots)
        need = 1 if LOOSE else 3
        dumped = 0
        for addr, v0 in sorted(a0.items()):
            seq = [s.get(addr) for s in shots]
            if any(v is None for v in seq) or max(seq) == min(seq):
                continue
            dumped += 1
            if dumped > 4000:
                break
            f0 = struct.unpack("<f", struct.pack("<I", v0))[0]
            out("DUMP %#011x i0=%d f0=%g %s" % (
                addr, v0, f0, " ".join("-" if v is None else str(v) for v in seq)))
        out("CHANGED %d" % dumped)
        if not dumped:                     # nothing moved: still leave a sample to read
            for addr in sorted(a0)[:400]:
                v0 = a0[addr]
                out("DUMP %#011x i0=%d f0=%g" % (
                    addr, v0, struct.unpack("<f", struct.pack("<I", v0))[0]))

        cands = []
        for addr, v0 in a0.items():
            seq = [s.get(addr) for s in shots]
            if any(v is None for v in seq):
                continue
            f0 = struct.unpack("<f", struct.pack("<I", v0))[0]
            if not ((1 <= v0 <= 250) or (1.0 <= f0 <= 250.0)):
                continue
            for i in range(1, n):
                if seq[i - 1] - seq[i] < need:
                    continue
                lo = seq[i]
                tail = seq[i:]
                if max(tail) - min(tail) > 2:      # must hold, not churn
                    continue
                cands.append((seq[0] - lo, addr, i, seq[0], lo, f0))
                break
        cands.sort(reverse=True)
        out("CANDIDATES %d" % len(cands))
        for d, addr, i, v0, v1, f0 in cands[:20]:
            out("CAND %#011x %d -> %d at shot%d (f0=%g) delta=%d" % (addr, v0, v1, i, f0, d))
        out("VERDICT %s" % ("candidate" if cands else "no-drop"))
        return 0 if cands else 1
    finally:
        g.close()
        out.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
