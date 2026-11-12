"""h34t: pre-reboot baseline - is the 1450 wall size-dependent on a GOOD page?

p135b's exhaustion signature was 4 KB 20/20, 64 KB -, 1 MB 3/20, 4 MB 0/20.
_mk5 just proved the DTB frame refuses instantly at 4 KB while ctrl reads
20/20.  One variable: request size on the known-good ctrl page (R5), capped
at 1 MB so nothing can wedge (FACTS: 4 MB+ ioctls hang gdrv3).  One shot at
each size on the dead frame for the record.  This file is the pre-state the
post-reboot gate (PLAN queue #1: 1 MB back near 700 MB/s) compares against.

Pure read probe, gdrv3 only.
"""
import os
import sys
import time

sys.path.insert(0, "..\\ext")
import dumplive as dl          # noqa: E402
import gio                     # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_mk6_out.txt")
CTRL = 0x436A00000
FRAME = 0x6EF568000
SIZES = (0x1000, 0x10000, 0x100000)     # 4 KB, 64 KB, 1 MB - never >= 4 MB
N = 10


def say(s):
    line = str(s)
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % __file__))
        return 0
    open(OUT, "w").close()
    say("=== mk6 size ladder (pre-reboot baseline) %s ==="
        % time.strftime("%H:%M:%S"))
    ranges, note = dl.usable_ranges(0, 0x1000, None)
    say("ranges=%d (%s)" % (len(ranges), note))
    for tag, pa in (("ctrl", CTRL), ("frame", FRAME)):
        p = pa & ~0xFFF
        if not any(a <= p and p + 0x1000 <= b for a, b in ranges):
            say("%s %#x NOT in usable map - skipped (R10)" % (tag, pa))
            continue

    for size in SIZES:
        g = gio.Gio(chunk=size)
        ok, err, us = 0, {}, 0.0
        for _ in range(N):
            t0 = time.perf_counter()
            try:
                g.read_phys(CTRL, size)
                ok += 1
            except OSError as e:
                err[e.errno] = err.get(e.errno, 0) + 1
            us += time.perf_counter() - t0
        mbs = (ok * size) / max(us, 1e-6) / 1e6
        say("ctrl  %6d B: %2d/%d READ  %.1f MB/s  errs=%s"
            % (size, ok, N, mbs, err or "-"))
        try:
            g.read_phys(FRAME, size)
            say("frame %6d B: READ (!)" % size)
        except OSError as e:
            say("frame %6d B: e%s" % (size, e.errno))
        g.close()
    say("RESULT: baseline recorded (compare PLAN gate: 1 MB ~700 MB/s "
        "post-reboot)")
    say("VERDICT: INFO - pre-reboot state captured")
    return 0


if __name__ == "__main__":
    sys.exit(main())
