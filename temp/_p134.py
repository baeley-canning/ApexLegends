r"""_p134.py -- PROBE p134: full-RAM pos-first census, numpy scanner, stride-partner filter.

p132 passed on 2.5 % coverage (11.6 MB/s was the Python scan loop, not the driver: one ioctl
does 1 MB in 1.3 ms).  p133's dump showed why junk dominates: the player block is bone transforms
- translation scalars interleaved with unit quaternions - so single plausible triples are
wall-to-wall.  Two filters kill that noise:
  * vectorised plausibility (same bounds as p124-p133), and
  * a PARTNER requirement: another plausible triple at +-0xC0 or +-0xC8 (the two record families
    p133's stride walk measured).  Isolated quats/singletons die; array members survive.

Then the p132 protocol unchanged: pass1 -> walk -> pass2 -> diff (walking-scale displacement) ->
targeted pass3 -> junk keeps moving, the walked body stops.  Coherent stops = player records.
PASS prints seeds for p135's autopsy.  Angle-free, name-free, no typing.

Every read is watchdogged.  Read-only, gdrv3.  Safe to re-run.
Writes temp\_p134_out.txt.  RESULT:/VERDICT: name the variable (R5).
Usage: _p134.py [--budget=100] [--walk=12] [--fmt=float|double] [--cap=3000]
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

OUT = os.path.join(HERE, "_p134_out.txt")
CHUNK = 0x100000       # 4 MB wedges gdrv3; 1 MB does 1.3 ms/ioctl (p132b bench)
LO_D = 150.0           # below this a "move" is micro-jitter
HI_D = 20000.0         # sprint is ~320 u/s, a pass window is <= 100 s
SPAN = 150.0
PARTNERS = (0xC0, 0xC8)
LEAK_CAP = 6
F32 = np.dtype("<f4")


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def timed_read(g, pa, n, secs=3.0):
    box = {}

    def work():
        # p137: a 1450 returns INSTANTLY (it is a refusal, not a timeout) and 1 MB raw runs
        # at ~750 MB/s, so the cure is an immediate re-try, not a sleep.  Per-attempt success
        # is ~25-60 %, so 12 tries give ~95 % per visit for ~8 ms worst case - three passes
        # over the same address push the miss probability under 0.1 %.
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
        return None, True
    return box.get("b"), False


def scan(b, base, fmt, addrs, vals):
    if fmt == "double":
        v = np.frombuffer(b, "<f8")
        step = 8
    else:
        v = np.frombuffer(b, F32)
        step = 4
    n = len(v)
    if n < 8:
        return
    av = np.abs(v)
    fin = np.isfinite(v) & (av > 1e-6) & (av < 1e7)
    t = fin[:-2] & fin[1:-1] & fin[2:]
    t &= (av[:-2] < 12000) & (av[1:-1] < 4000) & (av[2:] < 12000)
    t &= (av[:-2] > 250) | (av[2:] > 250)
    keep = np.zeros(n - 2, dtype=bool)
    for st in PARTNERS:
        e = st // step
        if e < n - 2:
            keep[:len(keep) - e] |= t[e:]
            keep[e:] |= t[:len(keep) - e]
    t &= keep
    idx = np.nonzero(t)[0]
    if not len(idx):
        return
    addrs.append(base + idx.astype(np.int64) * step)
    vals.append(np.stack([v[idx], v[idx + 1], v[idx + 2]], 1))


def sweep(g, ranges, budget, fmt, tag):
    addrs, vals, swept, leaked, t0 = [], [], 0, 0, time.time()
    for rlo, rhi in ranges:
        pa = (rlo + 7) & ~7
        while pa + CHUNK <= rhi:
            if time.time() - t0 > budget or leaked > LEAK_CAP:
                say("  %s aborted t=%.0fs swept=%#x leaked=%d"
                    % (tag, time.time() - t0, swept, leaked))
                return addrs, vals, swept
            b, wedge = timed_read(g, pa, CHUNK)
            if wedge:
                leaked += 1
                pa += 0x1000
                continue
            if b:
                scan(b, pa, fmt, addrs, vals)
                swept += len(b)
                if (swept >> 22) != ((swept - len(b)) >> 22):
                    say("  %s %5.0f MB %.0f MB/s" % (tag, swept / 1e6,
                                                     swept / max(time.time() - t0, 1e-3) / 1e6))
            pa += CHUNK
    say("  %s done t=%.0fs swept=%#x leaked=%d" % (tag, time.time() - t0, swept, leaked))
    return addrs, vals, swept


def cat(addrs, vals):
    if not addrs:
        return np.zeros(0, np.int64), np.zeros((0, 3), F32)
    return np.concatenate(addrs), np.concatenate(vals).astype(F32)


def main():
    budget, walk, fmt, cap = 100, 12, "float", 3000
    for a in sys.argv:
        if a.startswith("--budget="):
            budget = int(a.split("=", 1)[1])
        elif a.startswith("--walk="):
            walk = int(a.split("=", 1)[1])
        elif a.startswith("--fmt="):
            fmt = a.split("=", 1)[1]
        elif a.startswith("--cap="):
            cap = int(a.split("=", 1)[1])
        elif a.startswith("--chunk="):
            globals()["CHUNK"] = int(a.split("=", 1)[1], 0)
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" --budget=%d --walk=%d --fmt=%s --cap=%d --chunk=%#x'
                            % (os.path.abspath(__file__), budget, walk, fmt, cap, CHUNK)))
        return 0
    open(OUT, "w").close()

    say("=== p134 full census %s fmt=%s budget=%ds walk=%ds cap=%d stride=%s ==="
        % (time.strftime("%H:%M:%S"), fmt, budget, walk, cap, PARTNERS))
    pid = dl.find_pid()
    say("game_pid=%s" % pid)
    if pid is None:
        say("RESULT: game_pid=none")
        say("VERDICT: PARTIAL - game not running (R9)")
        return 3
    try:
        g = gio.Gio(chunk=CHUNK)
    except OSError as e:
        say("gio: %s" % e)
        return 2

    ranges, rnote = dl.usable_ranges(g.ram_top, 0x1000, None)
    say("ranges=%d note=%s ram_top=%#x total=%#x"
        % (len(ranges), rnote, g.ram_top, sum(h - l for l, h in ranges)))
    t0 = time.time()
    say(">>> pass1 collecting")
    a1, v1, s1 = sweep(g, ranges, budget, fmt, "p1")
    A1, V1 = cat(a1, v1)
    say("pass1 %s: cand=%d swept=%#x" % (time.strftime("%H:%M:%S"), len(A1), s1))
    say(">>> WALK ~20 m now for %ds" % walk)
    time.sleep(walk)
    say(">>> pass2 collecting (keep walking until STOP)")
    a2, v2, s2 = sweep(g, ranges, budget, fmt, "p2")
    A2, V2 = cat(a2, v2)
    say("pass2 %s: cand=%d swept=%#x" % (time.strftime("%H:%M:%S"), len(A2), s2))
    say(">>> STOP walking")
    time.sleep(1)

    if not len(A1) or not len(A2):
        say("RESULT: cand p1=%d p2=%d" % (len(A1), len(A2)))
        say("VERDICT: FAIL - one pass collected nothing")
        return 1

    common, i1, i2 = np.intersect1d(A1, A2, assume_unique=True, return_indices=True)
    d = np.sqrt(((V2[i2] - V1[i1]) ** 2).sum(1))
    m = (d >= LO_D) & (d <= HI_D)
    M, Pv, D = common[m], V2[i2][m], d[m]
    say("common=%d moved=%d (%.0f..%.0f units) t=%.0fs"
        % (len(common), len(M), LO_D, HI_D, time.time() - t0))
    if not len(M):
        say("RESULT: common=%d moved=0" % len(common))
        say("VERDICT: FAIL - nothing moved by a walking-scale delta")
        return 1

    o = np.argsort(-D)[:cap]
    M, Pv, D = M[o], Pv[o], D[o]
    still, stop, stopA = 0, 0, []
    for i in range(len(M)):
        b, wedge = timed_read(g, int(M[i]), 12)
        if wedge or not b or len(b) < 12:
            continue
        v3 = np.frombuffer(b[:12], F32)
        if float(np.sqrt(((v3 - Pv[i]) ** 2).sum())) >= 40.0:
            still += 1
        else:
            stop += 1
            stopA.append(i)
    say("pass3 over %d: stop=%d still=%d" % (len(M), stop, still))

    seeds = 0
    if stopA:
        j = np.argsort(Pv[stopA, 0])
        S, P2s, Ds = M[stopA][j], Pv[stopA][j], D[stopA][j]
        groups, cur = [], [0]
        for i in range(1, len(S)):
            if P2s[i, 0] - P2s[cur[0], 0] <= SPAN and abs(P2s[i, 2] - P2s[cur[0], 2]) <= SPAN:
                cur.append(i)
            else:
                groups.append(cur)
                cur = [i]
        groups.append(cur)
        groups.sort(key=len, reverse=True)
        say("stop-clusters=%d" % len(groups))
        for gi, grp in enumerate(groups[:8]):
            mv = float(Ds[grp].mean())
            say("  c%d n=%d mean_len=%.0f" % (gi, len(grp), mv))
            for i in grp[:8]:
                coh = abs(Ds[i] - mv) <= 0.35 * max(mv, 1.0)
                say("    @%#011x %10.2f %8.2f %10.2f len=%.0f%s"
                    % (S[i], P2s[i, 0], P2s[i, 1], P2s[i, 2], Ds[i], " COH" if coh else ""))
                if coh and seeds < 24:
                    seeds += 1
                    say("    SEED %#x" % S[i])
    say("RESULT: moved=%d stop=%d still=%d seeds=%d" % (len(M), stop, still, seeds))
    if seeds:
        say("VERDICT: PASS - %d coherent walked-then-stopped triple(s) with stride partners"
            % seeds)
        return 0
    say("VERDICT: FAIL - no coherent stop triple")
    return 1


if __name__ == "__main__":
    sys.exit(main())
