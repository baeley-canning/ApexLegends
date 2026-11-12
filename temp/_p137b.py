r"""_p137b.py -- zero-backoff retry test at 1 MB and 2 MB.

p137: 1 MB raw succeeds 60% and every 1450 returns INSTANTLY (0.0 s for 40 attempts, 749.7
MB/s) while a 20 ms backoff only reaches 25 MB/s.  The failures are not latency, they are
refusals, so the cure is an immediate re-try on the same handle, not a sleep.  This probe
measures what an immediate re-try (tries=6, no sleep) does to success rate and wall time -
the number p134 needs for its chunk+policy constants.

Read-only, gdrv3, safe to re-run.  Writes temp\_p137b_out.txt.
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import gio
import dumplive as dl

OUT = os.path.join(HERE, "_p137b_out.txt")
N = 60
STEP = 0x2000000
WIN = 0x40000000
TRIES = 6
PHASES = [(0x100000, TRIES), (0x200000, TRIES), (0x400000, TRIES)]


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def phase(base, size, tries, tag):
    try:
        g = gio.Gio(chunk=size)
    except OSError as e:
        say("%s: open failed %s" % (tag, e))
        return None
    ok = 0
    att = 0
    errs = {}
    t0 = time.perf_counter()
    for i in range(N):
        pa = base + i * STEP
        for k in range(tries):
            att += 1
            try:
                g.read_phys(pa, size)
                ok += 1
                break
            except OSError as e:
                errs[e.errno] = errs.get(e.errno, 0) + 1
    dt = max(time.perf_counter() - t0, 1e-6)
    g.close()
    rate = ok * size / dt / 1e6
    say("%s: ok=%d/%d attempts=%d errs=%s %.2fs -> %.1f MB/s wall"
        % (tag, ok, N, att, errs or "-", dt, rate))
    return ok / float(N), rate


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== p137b zero-backoff retry %s ===" % time.strftime("%H:%M:%S"))
    probe = gio.Gio(chunk=0x1000)
    ranges, note = dl.usable_ranges(probe.ram_top, 0x1000, None)
    probe.close()
    base = None
    for lo, hi in ranges:
        if hi - lo >= WIN and lo >= 0x100000000:
            base = (lo + 0x1000) & ~0xFFFFF
            break
    if base is None:
        say("no usable window")
        return 1
    say("ranges=%d note=%s base=%#x n=%d tries=%d" % (len(ranges), note, base, N, TRIES))
    res = []
    for size, t in PHASES:
        r = phase(base, size, t, "%#08x immediate" % size)
        if r:
            res.append(("%#08x" % size, r[0], r[1]))
    say("")
    if not res:
        say("RESULT: none")
        say("VERDICT: FAIL - no phase ran")
        return 0
    best = max(res, key=lambda t: t[2])
    say("RESULT: best=%s ok=%.0f%% wall=%.1f MB/s" % (best[0], best[1] * 100, best[2]))
    good = [t for t in res if t[1] >= 0.99]
    if good:
        say("VERDICT: PASS - %s reaches %.0f%% with immediate re-try; full 27.8 GB pass = %.1f min"
            % (good[0][0], good[0][1] * 100, 27.8e3 / good[0][2] / 60))
    else:
        say("VERDICT: FAIL - immediate re-try does not reach 99%% (best %.0f%% %s)"
            % (best[1] * 100, best[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
