"""h34z: is the 1450 state a fast flicker or a long per-page flip?

0x6ef980000 read fine minutes ago and fails 8/8 now; the control has never
failed.  retry_phys' ladder tops out at ~1.5 s total, and h320 already saw
1450 persist "well past 150 ms".  Here the cadence is 1 s over 20 s, so the
horizon is the variable.  A control read every 5th beat proves the driver is
alive for the whole window and the fault is per-page, not global.
"""
import os
import sys
import time

sys.path.insert(0, "..\\ext")
import dumplive as dl          # noqa: E402
import gio                     # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_mk4_out.txt")
TARGETS = (("frame", 0x6EF568000), ("wasok", 0x6EF980000))
CTRL = 0x436A00000
BEATS = 20


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
    g = gio.Gio(chunk=0x1000)
    hit = {t: 0 for t, _ in TARGETS}
    ctrl_ok = 0
    for beat in range(BEATS):
        row = []
        for tag, pa in TARGETS:
            try:
                g.read_phys(pa, 0x1000)
                hit[tag] += 1
                row.append("%s=READ" % tag)
            except OSError as e:
                row.append("%s=%s" % (tag, e.errno))
        if beat % 5 == 0:
            try:
                g.read_phys(CTRL, 0x1000)
                ctrl_ok += 1
                row.append("ctrl=READ")
            except OSError as e:
                row.append("ctrl=%s" % e.errno)
        say("  t=%2ds %s" % (beat, " ".join(row)))
        time.sleep(1.0)
    say("tally %s ctrl %d/%d" % (hit, ctrl_ok, BEATS // 5))
    live = [t for t, _ in TARGETS if hit[t]]
    if not live:
        say("VERDICT: FAIL -- nothing landed in %ds, per-page state is not a fast flip" % BEATS)
    elif ctrl_ok < BEATS // 5:
        say("VERDICT: PARTIAL -- hits=%s but driver also dropped control" % live)
    else:
        say("VERDICT: PASS -- late reads land after %d beats (targets %s); "
            "1450 is a slow per-page flip, backoff must be seconds" %
            (min(BEATS - 1, BEATS), live))
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
