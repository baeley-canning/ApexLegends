r"""_p128.py -- PROBE p128: are the p127 positions live data or a static table?

p127 (VERDICT PASS at 0x14bc2d434) found 4 float triples that satisfy 2+ names, but every one
has x=0.00 and y=0.00 and they sit 0x7B34 before their name cluster, 0x210 apart - the shape of
a constant array, not of a player.  p127's own gate only required |x| or |z| >= 250, so
0.00 0.00 3362.01 passes on the z component alone.

The variable this probe changes: TIME.  A real entity moves, a table does not.

Pass 1 reads every address, pass 2 reads the same addresses 6 s later and diffs them.  A field
that changed between passes is live; one that is byte-identical is a constant.  Names are
re-verified at the same time so a freed cluster is not mistaken for a moved one.

Read-only, gdrv3 only.  Writes temp\_p128_out.txt.
RESULT:/VERDICT: name the variable (R5).  Usage: _p128.py [--secs=N] [--wait=N]
"""
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import gio
import dumplive as dl

OUT = os.path.join(HERE, "_p128_out.txt")
NEEDLES = ["kern30120", "spanner1981", "Gen X Gaming"]

# from temp\_p127_out.txt - the only positions p127 produced, and the cluster they hang off
POS = [0x14bc2d434, 0x14bc2d644, 0x14bc2d790, 0x14bc2d858]
CLUSTER = 0x14bc25900
BACK = 0x60          # read this far before each address
FWD = 0x60           # and this far after
GAP = 6              # seconds between the two passes


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def f32(b, o):
    import struct
    return struct.unpack("<f", b[o:o + 4])[0]


def pl(v):
    """plausible float: not denormal-borne int, not nan/inf, sane magnitude"""
    return v == v and abs(v) > 1e-6 and abs(v) < 1e7


def read(g, pa, n):
    try:
        b = dl.retry_phys(g, pa, n, tries=2)
    except Exception:                                          # noqa: BLE001
        return None
    return b if b and len(b) == n else None


def names_near(g, pa, span):
    pats = {n: n.encode("ascii") for n in NEEDLES}
    b = read(g, pa - span, span * 2)
    if b is None:
        return None
    return sorted(k for k, p in pats.items() if p in b)


def snapshot(g):
    snap = {}
    for pa in POS:
        snap[pa] = read(g, pa - BACK, BACK + FWD)
    return snap


def report(pa_name, tag, snap):
    for pa in POS:
        b = snap.get(pa)
        if b is None:
            say("  %s %#x UNREADABLE" % (tag, pa))
            continue
        say("  %s %#x +-0x%x:" % (tag, pa, BACK))
        row = []
        for o in range(0, len(b) - 3, 4):
            v = f32(b, o)
            row.append("%+.3f" % v if pl(v) else "....")
        for i in range(0, len(row), 8):
            say("    %+05x %s" % (i * 4 - BACK, " ".join(row[i:i + 8])))
        # triples: three consecutive plausible floats inside the accepted world ranges
        for o in range(0, len(b) - 11, 4):
            x, y, z = f32(b, o), f32(b, o + 4), f32(b, o + 8)
            if pl(x) and pl(y) and pl(z) and abs(x) < 12000 and abs(y) < 4000 and abs(z) < 12000:
                if abs(x) > 250 or abs(z) > 250:
                    say("    TRIPLE @%+#x  %.2f %.2f %.2f" % (o - BACK, x, y, z))


def diff(s1, s2):
    out = []
    for pa in POS:
        a, b = s1.get(pa), s2.get(pa)
        if a is None or b is None:
            out.append("%#x LOST" % pa)
            continue
        ch = [i for i in range(0, min(len(a), len(b)) - 3, 4) if a[i:i + 4] != b[i:i + 4]]
        if not ch:
            out.append("%#x STATIC (0 fields changed)" % pa)
            continue
        desc = []
        for i in ch[:8]:
            desc.append("%+#x %.3f->%.3f" % (i - BACK, f32(a, i), f32(b, i)))
        out.append("%#x CHANGED %d fields: %s" % (pa, len(ch), ", ".join(desc)))
    return out


def main():
    secs = 180
    wait = 0
    for a in sys.argv:
        if a.startswith("--secs="):
            secs = int(a.split("=", 1)[1])
        elif a.startswith("--wait="):
            wait = int(a.split("=", 1)[1])
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" --secs=%d --wait=%d'
                            % (os.path.abspath(__file__), secs, wait)))
        return 0
    open(OUT, "w").close()

    t0 = time.time()
    pid = dl.find_pid()
    if pid is None and wait > 0:
        say("waiting up to %ds for r5apex_dx12" % wait)
        while pid is None and time.time() - t0 < wait:
            time.sleep(3)
            pid = dl.find_pid()
    say("=== p128 liveness of the p127 positions %s ===" % time.strftime("%H:%M:%S"))
    say("game_pid=%s" % pid)
    if pid is None:
        say("RESULT: game_pid=none")
        say("VERDICT: PARTIAL - game not running (R9)")
        return 3

    try:
        g = gio.Gio(chunk=0x100000)
    except OSError as e:
        say("gio: %s" % e)
        return 2

    near = names_near(g, CLUSTER, 0x800)
    say("names still near %#x: %s" % (CLUSTER, near))
    if not near:
        say("note: names gone from that cluster - addresses may be stale, diff is still read")

    s1 = snapshot(g)
    say("pass1 at %s" % time.strftime("%H:%M:%S"))
    report(None, "p1", s1)
    say("sleeping %ds, the player will move" % GAP)
    time.sleep(GAP)
    s2 = snapshot(g)
    say("pass2 at %s" % time.strftime("%H:%M:%S"))
    report(None, "p2", s2)

    say("--- diff ---")
    lines = diff(s1, s2)
    for L in lines:
        say("  " + L)
    live = [L for L in lines if "CHANGED" in L]

    say("RESULT: pos_live=%d/%d nameneedles=%d" % (len(live), len(POS), len(near or [])))
    if live:
        say("VERDICT: PASS - %d of %d positions are live (changed over %ds); %s"
            % (len(live), len(POS), GAP, live[0]))
    else:
        say("VERDICT: FAIL - all %d positions byte-identical over %ds: static table, not entities"
            % (len(POS), GAP))
    say("elapsed=%.0fs" % (time.time() - t0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
