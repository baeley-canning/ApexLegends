r"""_p137.py -- do backoff retries convert the 1450 storm, and at which chunk size?

p135b after the reboot: successes and 1450s are INTERLEAVED inside one tight loop
(4 KB 20/20, 64 KB 18/20, 1 MB 11/20, 4 MB 6/20, 16 MB 2/20).  A pure PTE leak gives N
successes then nothing; interleaving means the system PTEs of a just-unmapped ioctl are
released lazily and the next allocation races the release.  If that is right, a short
sleep between tries converts nearly every read and the census can run at 1 MB (0.75 GB/s
class) instead of 64 KB.

Three phases on ONE handle each, PAs stepping 0x2000000 inside a usable range:
  A  1 MB, no retry                      baseline rate of the raw ioctl
  B  1 MB, retry with 20 ms linear backoff
  C  1 MB, retry with 50 ms linear backoff (dumplive.RETRY_MS default shape)
  D  4 MB, retry with 50 ms linear backoff   fewer ioctls per GB
  E  64 KB, retry with 20 ms               known-good control
Counts and wall time are written per phase; the verdict names the best size+policy.
Read-only, gdrv3, safe to re-run.  Writes temp\_p137_out.txt.
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import gio
import dumplive as dl

OUT = os.path.join(HERE, "_p137_out.txt")
N = 40
STEP = 0x2000000
WIN = 0x40000000
PHASES = [(0x100000, 0), (0x100000, 20), (0x100000, 50), (0x400000, 50), (0x10000, 20)]


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def phase(base, size, backoff, tag):
    try:
        g = gio.Gio(chunk=size)
    except OSError as e:
        say("%s: open failed %s" % (tag, e))
        return None
    ok = 0
    errs = {}
    t0 = time.perf_counter()
    for i in range(N):
        pa = base + i * STEP
        tries = 3 if backoff else 1
        got = False
        for k in range(tries):
            try:
                g.read_phys(pa, size)
                got = True
                break
            except OSError as e:
                errs[e.errno] = errs.get(e.errno, 0) + 1
                if k < tries - 1:
                    time.sleep(backoff / 1000.0 * (k + 1))
        ok += 1 if got else 0
    dt = max(time.perf_counter() - t0, 1e-6)
    g.close()
    rate = ok * size / dt / 1e6
    say("%s: ok=%d/%d errs=%s %.1fs -> %.1f MB/s wall"
        % (tag, ok, N, errs or "-", dt, rate))
    return ok / float(N), rate


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== p137 retry-vs-1450 %s ===" % time.strftime("%H:%M:%S"))
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
    say("ranges=%d note=%s base=%#x n=%d step=%#x" % (len(ranges), note, base, N, STEP))
    res = []
    for size, bo in PHASES:
        tag = "%#08x bo=%2dms" % (size, bo)
        r = phase(base, size, bo, tag)
        if r:
            res.append((tag, r[0], r[1]))
    say("")
    for tag, frac, rate in res:
        say("summary %s ok=%.0f%% wall=%.1f MB/s" % (tag, frac * 100, rate))
    if not res:
        say("RESULT: none")
        say("VERDICT: FAIL - no phase ran")
        return 0
    best = max(res, key=lambda t: t[2])
    say("RESULT: best=%s ok=%.0f%% wall=%.1f MB/s" % (best[0], best[1] * 100, best[2]))
    conv = [t for t in res if t[1] >= 0.95 and t[2] > 0]
    if conv:
        say("VERDICT: PASS - %s converts >=95%% of reads; full 27.8 GB pass = %.1f min"
            % (conv[0][0], 27.8e3 / conv[0][2] / 60))
    else:
        say("VERDICT: FAIL - no size+backoff combination reaches 95%% success")
    return 0


if __name__ == "__main__":
    sys.exit(main())
