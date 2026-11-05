r"""p64_pairs.py -- find the local player's health by its full-health cluster signature.

p62 proved the transport is fine at page granularity (3924/3931 pages readable; 64 KiB
chunk reads are what break) but the p61 name anchor sits in a name pool that holds no
100.0f at all -- 32 MiB around it yielded 3 unaligned float hits. So this probe drops
the anchor: it sweeps the full band for 4-byte-ALIGNED 100.0f and keeps only clusters of
three or more inside 0x80 -- health, max-health and shield on a full-health player. A
lone 100.0f in geometry cannot form that cluster, and geometry does not hold still.

Filters, in this order: aligned 100.0f -> >=3 of them within 0x80 -> every member still
exactly 100 after a 1.5 s gap (kills churn) -> throw a grenade -> one member must fall
by >=5 and stay down 4 samples while all the others stay >=95.  The loser may recover
afterwards (a shield regenerates), so flatness is only required inside the hold window.
Shield absorbs first, so the health member falls only after the shield member has gone
to 0; both are recorded either way.

Usage: python ext\p64_pairs.py [--band=full|all] [--win=0x80] [--min=3] [--cap=6000]
       [--pre=12] [--wait=15] [--shots=8] [--every=1.5] [--out=path] [--collect-only]
       [--seed=file] [--seed-out=file] [--nade2=8,16,24] [--chain]

--chain is the real shape: one fixed cue (frag 1) fires at --nade2, then a second cue fires on
state, not on a shot number -- only once a member actually reads 0.  Frag 2 therefore lands on a
bare 0 armour pool and eats health until the pawn is downed (frag 1 strips the pool, frag 2 takes
health; a third nade is never needed).  The cue re-arms every 4 empty samples so a mis-timed throw
does not end the run.  Fixed shot numbers miss because the frag flies 1.5-2 s and the pool can be
mid-refill while it is in the air.

--min=2 is the damaged-player mode: a hurt pawn keeps two 100.0f (health-max,
shield-max) but loses the third, so the nade shape test has to do the filtering.
--seed skips the sweep and re-checks the listed clusters only (0.7 s cadence).

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
    """Audible cue -- the player is looking at the game, not the console."""
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
F100 = 0x42C80000
SHOTS = 8
EVERY = 1.5
NEED = 5.0             # drop required on the health member
KEEP = 95.0            # every other member must stay at least this high
HOLD = 4               # samples the drop has to stay down (recovery allowed after)
MIN_MEM = 3            # aligned 100.0f needed inside one span
MEM_MAX = 8            # members kept per cluster
CL_CAP = 6000          # clusters tracked per shot; page-batched reads keep a shot < 1 s


class Out(object):
    def __init__(self, path):
        self.h = open(path, "w", encoding="utf-8")

    def __call__(self, s):
        print(s)
        self.h.write(s + "\n")
        self.h.flush()

    def close(self):
        self.h.close()


def f(u):
    return struct.unpack("<f", struct.pack("<I", u))[0]


def collect(g, lo, hi, win, out):
    """Clusters of >=MIN_MEM aligned 100.0f inside a span of win -- full health+shield."""
    hit = []
    t0 = time.time()
    faults = 0

    def emit(pa, blk):
        nonlocal faults
        if blk is None:
            faults += 1
            return
        i = blk.find(F32_100)
        while i >= 0:
            a = pa + i
            if a & 3 == 0:
                hit.append(a)
            elif blk[i - 1:i + 3] == F32_100:
                hit.append(a + 3)      # value straddled a chunk edge, aligned form
            i = blk.find(F32_100, i + 1)

    pa = lo
    while pa < hi:
        p56_hits.scan_range(g, pa, min(CHUNK, hi - pa), b"d", False, emit)
        pa += CHUNK
    hit = sorted(set(a for a in hit if lo <= a < hi))
    out("COLLECT %#x-%#x aligned100=%d faults=%d secs=%.1f" % (
        lo, hi, len(hit), faults, time.time() - t0))
    clus, seen = [], set()
    for i in range(len(hit)):
        base = hit[i]
        if base in seen:
            continue
        mem = [a for a in hit[i:i + MEM_MAX * 4] if a <= base + win][:MEM_MAX]
        if len(mem) < MIN_MEM:
            continue
        seen.update(mem)
        clus.append((base, mem))
    out("CLUSTERS %d (min_mem=%d span=%#x)" % (len(clus), MIN_MEM, win))
    return clus


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


def snapshot(g, clus):
    """One page-read pass over every member -> {base: [values]}."""
    flat = [a for _, mem in clus for a in mem]
    v = sample(g, flat)
    return dict((base, [v[a] for a in mem]) for base, mem in clus)


def verdict(series):
    """One member falls >= NEED, stays down HOLD samples, all others stay >= KEEP.

    The member may recover afterwards -- a spent shield comes back, so "flat to
    the end of the run" is the wrong test; the hold window is what separates a
    real field from churn.  Returning the largest drop keeps the shield member
    (100 -> 0) ahead of a health member that only loses frag spill (R3).
    """
    cur = [[f(x) for x in s] for s in series]
    n = len(cur[0])
    best = None
    for k in range(len(cur)):
        for i in range(1, n):
            d = cur[k][i - 1] - cur[k][i]
            if d < NEED:
                continue
            hold = cur[k][i:i + HOLD]
            if len(hold) < min(HOLD, n - i):
                continue
            if max(hold) - min(hold) > 2.0:
                continue
            if max(hold) > cur[k][i - 1] - NEED / 2.0:    # still visibly down
                continue
            bad = False
            for o in range(len(cur)):
                if o == k or cur[o][0] < KEEP:            # 0 = already spent partner
                    continue
                lo_o = min(cur[o][i - 1:i + HOLD])
                if 1.0 < lo_o < KEEP:                     # moved, but not emptied
                    bad = True
                    break
            if bad:
                continue
            if best is None or d > best[0]:
                best = (d, i, k)
    return best


def load_seed(path, out):
    """Read 'base off,off,...' hex lines written by a previous run's --seed-out."""
    clus = []
    with open(path, "r") as fh:
        for ln in fh:
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            pb, po = ln.split()
            b = int(pb, 16)
            clus.append((b, [b + int(o, 16) for o in po.split(",")]))
    out("SEED %d clusters from %s" % (len(clus), os.path.basename(path)))
    return clus


def main(argv):
    band, win = "full", 0x100
    out_path = os.path.join(ROOT, "temp", "p64_%s.txt" % time.strftime("%Y%m%d_%H%M%S"))
    pre, wait, only, cues, chain = 12.0, 15.0, False, [], False
    seed, seed_out = "", ""
    for a in argv:
        if a.startswith("--band="):
            band = a[7:]
        elif a.startswith("--win="):
            win = int(a[6:], 0)
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
        elif a.startswith("--nade2="):
            cues = [int(x, 0) for x in a[8:].split(",") if x]
        elif a.startswith("--min="):
            globals()["MIN_MEM"] = int(a[6:], 0)
        elif a.startswith("--cap="):
            globals()["CL_CAP"] = int(a[6:], 0)
        elif a.startswith("--seed="):
            seed = a[7:]
        elif a.startswith("--seed-out="):
            seed_out = a[11:]
        elif a == "--chain":
            chain = True
        elif a == "--collect-only":
            only = True

    out = Out(out_path)
    out("# p64_pairs %s band=%s win=%#x min=%d" % (time.strftime("%Y-%m-%d %H:%M:%S"), band, win, MIN_MEM))
    g = None
    try:
        g = gio.Gio()
        if band == "all":
            lo, hi = 0x100000, g.ram_top
        else:
            lo, hi = FULL
        if seed:
            clus = load_seed(seed, out)
        else:
            clus = collect(g, lo, hi, win, out)
        if only:
            out("VERDICT collected")
            return 0
        if len(clus) > CL_CAP:
            k = len(clus) // CL_CAP + 1
            clus = clus[::k]
            out("SUBSAMPLE stride=%d clusters=%d" % (k, len(clus)))

        if wait > 0:
            out("CUES  880Hz short = countdown before GO (nades already in hand)")
            out("      1400Hz x3   = GO, throw frag 1 at your feet")
            out("      500Hz x2    = THROW the next frag NOW (frag 1 armour, frag 2 health)")
            out("      after frag 2 you go down: hold still, do NOT self-revive")
            out("      no beep     = stand still, do not throw")
            out("READY wait=%.0fs (drink up so armour is FULL%s)" % (
                wait, ", %d nades, cues = low double beeps" % (len(cues) + 1) if cues
                else ", no nades"))
            time.sleep(wait)
        # churn filter: unchanged across the gap; a sweep also requires exactly 100
        first = snapshot(g, clus)
        time.sleep(1.5)
        again = snapshot(g, clus)
        ok = lambda d, b: d[b] == [F100] * len(d[b])          # noqa: E731
        stable = [c for c in clus if (first[c[0]] == again[c[0]] if seed else
                                      ok(first, c[0]) and ok(again, c[0]))]
        out("STABLE %d of %d" % (len(stable), len(clus)))
        for t in range(int(pre), 0, -1):
            out("NADE NOW %d  <- one frag at your feet (countdown, then GO)" % t)
            beep(880, 120)
            time.sleep(1.0)
        beep(1400, 500)
        beep(1400, 500)
        beep(1400, 500)
        out("GO  <- start THROWING now: frag 1 strips the armour, frag 2 takes health")
        series = dict((b, [[v] for v in again[b]]) for b, m in stable)
        fell = dict((b, {}) for b, m in stable)
        for b, _ in stable:
            out("PRE %#011x %s" % (b, "/".join("%g" % f(v) for v in again[b])))
        t0 = time.time()
        last_cue = 0
        fired = False
        chained = False
        empty_run = 0
        last_empty_cue = 0
        downed = False
        for i in range(1, SHOTS):
            time.sleep(EVERY)
            if i in cues:
                act = "THROW"
            elif i - last_cue <= HOLD + 1:
                act = "RECOVER"
            else:
                act = "STILL"
            if act == "THROW":
                beep(500, 220)
                beep(500, 220)
                last_cue = i
                fired = True
                out("NADE %d NOW  <- THROW at your feet (1 strips armour, 2 takes health)"
                    % (cues.index(i) + 2))
            elif act == "RECOVER":
                out("RECOVER  <- stand still, no throw (shield should be refilling)")
            got = snapshot(g, stable)
            for b, _ in stable:
                for k, gv in enumerate(got[b]):
                    series[b][k].append(gv if gv is not None else None)
                    if gv is not None and f(gv) <= 1.0 and f(again[b][k]) >= 50.0:
                        fell[b][k] = True
            if not downed and any(sum(1 for v in fell[b].values() if v) >= 2
                                  for b, _ in stable):
                downed = True
                act = "DOWNED"
                out("DOWNED  <- you are on the floor: hold still, do NOT self-revive,")
                out("           the revive bar is being sampled; tell me if it moves")
            # chain cue: a second frag only once the shield reads empty, so the
            # damage has nowhere to go but health.  Fixed shot numbers miss this
            # because the frag flies 1.5-2 s and the shield can be mid-refill.
            if chain and fired:
                empty = any(got[b][k] is not None and f(got[b][k]) <= 1.0
                            for b, _ in stable for k in range(len(got[b])))
                empty_run = empty_run + 1 if empty else 0
                # first nade-3 cue as soon as the shield is seen empty and no cue is
                # in flight; after that re-cue every 4 shots so a missed throw is not
                # the end of the run (the pool stays empty, health never gets tested).
                if empty_run >= 1 and not chained and i - last_cue >= 2:
                    chained = True
                if empty_run >= 1 and ((chained and i - last_empty_cue >= 4)
                                       or not chained and i - last_cue >= 2):
                    last_empty_cue = i
                    act = "THROW"
                    last_cue = i
                    beep(500, 220)
                    beep(500, 220)
                    out("NADE %d NOW  <- shield is EMPTY, THROW again (this one hits health)"
                        "; then drink if you want" % (len(cues) + 2))
            chg = 0
            for b, _ in stable:
                for s in series[b]:
                    if s[-1] != s[-2]:
                        chg += 1
            out("shot %d [%s] clusters=%d chg=%d t=%.1fs" % (i, act, len(stable), chg,
                                                            time.time() - t0))

        cands = []
        mv = []
        for b, mem in stable:
            if any(v is None for s in series[b] for v in s):
                continue
            r = verdict(series[b])
            if r:
                cands.append((r[0], b, mem[r[2]], mem, r[1]))
            amp = max(max(s) - min(s) for s in series[b])
            if amp > 0.01:
                mv.append((amp, b, mem))
        mv.sort(reverse=True)
        out("MOVED %d of %d" % (len(mv), len(stable)))
        for amp, b, mem in mv[:6]:
            out("MOVE %#011x amp=%.1f %s" % (b, amp, " ".join(
                "%#x:%s" % (m - b, "/".join("%g" % f(v) for v in series[b][k]))
                for k, m in enumerate(mem))))
        cands.sort(reverse=True)
        out("CANDIDATES %d" % len(cands))
        for d, base, hit, mem, i in cands[:20]:
            out("CAND base=%#011x health=%#011x drop=%.1f at shot%d offs=%s" % (
                base, hit, d, i, ",".join("%#x" % (m - base) for m in mem)))
        for d, base, hit, mem, i in cands[:5]:
            out("TRACE %#011x %s" % (base, " ".join(
                "%#x:%s" % (m - base, "/".join(
                    "-" if v is None else "%g" % f(v) for v in series[base][k]))
                for k, m in enumerate(mem))))
        out("VERDICT %s" % ("cluster" if cands else "no-cluster"))
        if seed_out and cands:
            with open(seed_out, "w") as fh:
                fh.write("# base offs from %s\n" % os.path.basename(out_path))
                for d, base, hit, mem, i in cands:
                    fh.write("%#x %s\n" % (base, ",".join("%#x" % (m - base) for m in mem)))
            out("SEEDOUT %s n=%d" % (os.path.basename(seed_out), len(cands)))
        return 0 if cands else 1
    except Exception as e:                 # noqa: BLE001 -- the file is the state feed
        out("FATAL %s: %s" % (type(e).__name__, e))
        out("VERDICT error")
        return 5
    finally:
        if g is not None:
            g.close()
        out.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
