r"""_p132b_bench.py -- gio chunk-size bench (read-only).

p132 measured 11.6 MB/s at 1 MB chunks: ~86 ms per ioctl is MmMapIoSpace latency, not
bandwidth, so throughput should scale with chunk size until the driver or the mapping
breaks.  A full usable-RAM sweep is the census's engine; if the chunk cannot grow the
whole pos-first design costs hours per pass.

Alternating order (1,16,4,8,2,16,1 MB), same 32 MB window inside a usable range, best of
two per size.  errno 1450 aborts that size (gdrv3 is known-flaky on big requests).

Writes temp\_p132b_out.txt.  RESULT:/VERDICT: name the variable (R5).
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import gio
import dumplive as dl

OUT = os.path.join(HERE, "_p132b_out.txt")
WIN = 32 << 20
SIZES = [1 << 20, 16 << 20, 4 << 20, 8 << 20, 2 << 20, 16 << 20, 1 << 20]


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== p132b chunk bench %s ===" % time.strftime("%H:%M:%S"))
    try:
        probe = gio.Gio(chunk=0x1000)
    except OSError as e:
        say("gio: %s" % e)
        return 2
    ranges, note = dl.usable_ranges(probe.ram_top, 0x1000, None)
    probe.close()
    base = None
    for lo, hi in ranges:
        if hi - lo >= WIN and lo >= 0x100000000:
            base = (lo + 0x1000) & ~0xFFFFF
            break
    if base is None:
        for lo, hi in ranges:
            if hi - lo >= WIN:
                base = (lo + 0x1000) & ~0xFFFFF
                break
    if base is None:
        say("no usable window")
        return 1
    say("ranges=%d note=%s base=%#x win=%#x" % (len(ranges), note, base, WIN))

    best = {}
    for mb in SIZES:
        try:
            g = gio.Gio(chunk=mb)
        except OSError as e:
            say("%4d MB: open failed %s" % (mb >> 20, e))
            continue
        t0 = time.perf_counter()
        err = ""
        done = 0
        try:
            for pa in range(base, base + WIN, mb):
                n = min(mb, base + WIN - pa)
                g.read_phys(pa, n)
                done += n
        except OSError as e:
            err = " err=%s after %#x" % (e, done)
        dt = max(time.perf_counter() - t0, 1e-6)
        g.close()
        r = done / dt / 1e6
        say("%4d MB: %.1f MB/s in %.2fs%s" % (mb >> 20, r, dt, err))
        if not err and r > best.get(mb >> 20, 0):
            best[mb >> 20] = r

    say("best per size: %s" % {k: "%.1f" % v for k, v in sorted(best.items())})
    rank = sorted(best.items(), key=lambda kv: -kv[1])
    say("RESULT: bench sizes=%d best=%dMB %.1f MB/s"
        % (len(best), rank[0][0], rank[0][1]) if rank else "RESULT: no size completed")
    fs = 0x6efb53000 / 1e9
    if rank:
        say("VERDICT: PASS - chunk %d MB is %.1fx the p132 1 MB rate; full %.1f GB pass at "
            "that rate = %.1f min" % (rank[0][0], rank[0][1] / 11.6, fs, fs * 1e3 / rank[0][1] / 60))
    else:
        say("VERDICT: FAIL - no chunk size completed the window")
    return 0


if __name__ == "__main__":
    sys.exit(main())
