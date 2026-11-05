r"""p62_drop.py -- value sweep (100.0f / 100 int) in a narrow window, then a timed nade diff.

The name anchor proved to sit in a churning allocation: every page around it went
unreadable within seconds (p61 rid 231330, VERDICT no-drop, CHANGED 0). So this
probe ignores the string and goes after the number: it collects every dword that
reads 100.0f (0x42C80000) or integer 100 inside a small window, re-reads exactly
those addresses across a thrown grenade, and reports only fields that lose >=3
points and then hold flat. Health subtracts; ammo noise and position churn do not.

Candidate pages are read individually, so the per-shot cost is pages x 4 KiB and
the whole window is never re-read after the collect.

Usage: python ext\p62_drop.py [--win=16] [--centre=0x...] [--full]
       [--pre=12] [--wait=15] [--shots=8] [--every=1.5] [--out=path]
       (default out temp\p62_<timestamp>.txt, never shared)

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
F32_100 = struct.pack("<I", 0x42C80000)
I32_100 = struct.pack("<I", 100)
SHOTS = 8
EVERY = 1.5
NEED = 3               # drop required to call a candidate
CAP = 60000            # addresses kept; stride-subsampled above this


class Out(object):
    def __init__(self, path):
        self.h = open(path, "w", encoding="utf-8")

    def __call__(self, s):
        print(s)
        self.h.write(s + "\n")
        self.h.flush()

    def close(self):
        self.h.close()


def collect(g, lo, hi, out):
    """addr -> (value, kind) for every dword that reads 100.0f or int 100."""
    found = {}
    t0 = time.time()
    faults = 0

    def emit(pa, blk):
        nonlocal faults
        if blk is None:
            faults += 1
            return
        for pat, kind in ((F32_100, "f"), (I32_100, "i")):
            i = blk.find(pat)
            while i >= 0:
                found[pa + i] = (struct.unpack_from("<I", blk, i)[0], kind)
                i = blk.find(pat, i + 1)

    pa = lo
    while pa < hi:
        p56_hits.scan_range(g, pa, min(CHUNK, hi - pa), b"d", False, emit)
        pa += CHUNK
    out("COLLECT %#x-%#x cands=%d faults=%d secs=%.1f" % (
        lo, hi, len(found), faults, time.time() - t0))
    return found


def sample(g, addrs):
    """Read only the pages holding addrs; None where the page faults."""
    pages = {}
    for a in addrs:
        pages.setdefault(a & ~0xFFF, []).append(a)
    vals = {}
    for p, lst in pages.items():
        try:
            buf = g.read_phys(p, PAGE)
        except OSError:
            for a in lst:
                vals[a] = None
            continue
        for a in lst:
            o = a - p
            vals[a] = struct.unpack_from("<I", buf, o)[0] if o + 4 <= PAGE else None
    return vals


def score(kind, seq):
    """Drop of NEED or more at some shot that then holds within 2 -> (delta, shot)."""
    if any(v is None for v in seq):
        return None
    for i in range(1, len(seq)):
        if kind == "i":
            dropped = seq[i - 1] - seq[i]
        else:
            dropped = struct.unpack("<f", struct.pack("<I", seq[i - 1]))[0] - \
                struct.unpack("<f", struct.pack("<I", seq[i]))[0]
        if dropped < NEED:
            continue
        tail = seq[i:]
        if kind == "i":
            if max(tail) - min(tail) > 2:
                continue
            return int(dropped), i
        tailf = [struct.unpack("<f", struct.pack("<I", v))[0] for v in tail]
        if max(tailf) - min(tailf) > 2.0:
            continue
        return dropped, i
    return None


def main(argv):
    centre, win, full = None, 16, False
    out_path = os.path.join(ROOT, "temp", "p62_%s.txt" % time.strftime("%Y%m%d_%H%M%S"))
    pre, wait = 12.0, 15.0
    for a in argv:
        if a.startswith("--centre="):
            centre = int(a[9:], 16)
        elif a.startswith("--win="):
            win = int(a[6:])
        elif a.startswith("--pre="):
            pre = float(a[6:])
        elif a.startswith("--wait="):
            wait = float(a[7:])
        elif a.startswith("--shots="):
            globals()["SHOTS"] = int(a[8:])
        elif a.startswith("--every="):
            globals()["EVERY"] = float(a[8:])
        elif a.startswith("--out="):
            out_path = a[6:]
        elif a == "--full":
            full = True
    if centre is None and not full:
        try:
            with open(os.path.join(ROOT, "temp", "p61_cluster.txt")) as f:
                centre = int(f.read().split()[0], 16)
        except (OSError, ValueError, IndexError):
            full = True

    out = Out(out_path)
    out("# p62_drop %s centre=%s win=%d full=%s" % (
        time.strftime("%Y-%m-%d %H:%M:%S"),
        "-" if centre is None else "%#x" % centre, win, full))
    g = gio.Gio()
    try:
        if full:
            lo, hi = FULL
        else:
            lo = max(FULL[0], centre - (win << 20))
            hi = min(FULL[1], centre + (win << 20))
        cands = collect(g, lo, hi, out)
        addrs = sorted(cands)
        if len(addrs) > CAP:
            k = len(addrs) // CAP + 1
            addrs = addrs[::k]

        if wait > 0:
            out("READY wait=%.0fs (stand clear, full armour)" % wait)
            time.sleep(wait)
        a0 = {a: cands[a][0] for a in addrs}
        out("PRE cands=%d int=%d float=%d" % (
            len(addrs), sum(cands[a][1] == "i" for a in addrs),
            sum(cands[a][1] == "f" for a in addrs)))
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
            shots.append(sample(g, addrs))
            out("shot %d read=%d" % (i, sum(v is not None for v in shots[-1].values())))

        cand = []
        gone = 0
        for a in addrs:
            seq = [s.get(a) for s in shots]
            if any(v is None for v in seq):
                gone += 1
                continue
            r = score(cands[a][1], seq)
            if r:
                d, i = r
                cand.append((d, a, i, a0[a], seq[i], cands[a][1]))
        out("UNREADABLE %d" % gone)
        cand.sort(reverse=True)
        out("CANDIDATES %d" % len(cand))
        for d, a, i, v0, v1, k in cand[:25]:
            f0 = struct.unpack("<f", struct.pack("<I", v0))[0]
            out("CAND %#011x %s %d -> %d at shot%d (f0=%g) delta=%g" % (
                a, k, v0, v1, i, f0, d))
        if not cand:
            for a in addrs[:60]:
                out("SAMPLE %#011x %s %d" % (a, cands[a][1], a0[a]))
        out("VERDICT %s" % ("drop" if cand else "no-drop"))
        return 0 if cand else 1
    except Exception as e:                 # noqa: BLE001 -- the file is the state feed
        out("FATAL %s: %s" % (type(e).__name__, e))
        out("VERDICT error")
        return 5
    finally:
        g.close()
        out.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
