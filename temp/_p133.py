r"""_p133.py -- PROBE p133: mettle dump around p132's walked-then-stopped seed.

p132 (pos-first census, PASS) found a coherent triple that MOVED when the player walked and went
STATIC when the player stopped, at 0x1aa07259c, and a second one 0x3C0 away at 0x1aa0721dc.
Around it: repeated records on a 0xC8/0x400 stride, flat float y=2.00 - a record array, which is
the enumeration source the ESP needs (read records each frame, no name typed, no full sweep).

This probe only describes the neighbourhood: what shares the record with the position, what the
stride family really is, and which small ints could be team/hp.  No mutation, read-only, gdrv3.

LIVE marking: the band around the seed is read twice 3 s apart; nothing is required of the
player, but mouse movement helps angle deltas stand out (turning changes yaw/pitch, not pos).

Writes temp\_p133_out.txt.  RESULT:/VERDICT: name the variable (R5).
Usage: _p133.py [--seed=0x1aa07259c]
"""
import os
import struct
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import gio
import dumplive as dl

OUT = os.path.join(HERE, "_p133_out.txt")
SEEDS = [0x1aa07259c, 0x1aa0721dc]
BAND = 0x200
STRIDES = [0xC0, 0xC8, 0x400, 0x800]
FLAT_Y = 2.0


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def pl(v):
    return v == v and 1e-6 < abs(v) < 1e7


def okT(v):
    return (pl(v[0]) and pl(v[1]) and pl(v[2])
            and abs(v[0]) < 12000 and abs(v[1]) < 4000 and abs(v[2]) < 12000
            and (abs(v[0]) > 250 or abs(v[2]) > 250))


def timed_read(g, pa, n, secs=2.0):
    box = {}

    def work():
        try:
            box["b"] = dl.retry_phys(g, pa, n, tries=2)
        except Exception:                                       # noqa: BLE001
            pass

    t = threading.Thread(target=work, daemon=True)
    t.start()
    t.join(secs)
    if t.is_alive():
        return None
    return box.get("b")


def band(g, pa):
    lo = pa - BAND
    b = timed_read(g, lo, BAND * 2)
    return (lo, b) if b else (0, None)


def dump(tag, lo, b):
    say("--- band %s lo=%#x len=%d" % (tag, lo, len(b)))
    shown = 0
    for o in range(0, len(b) - 3, 4):
        v = struct.unpack_from("<f", b, o)[0]
        i = struct.unpack_from("<i", b, o)[0]
        if v == v and (1e-6 < abs(v) < 12000 or 0 < i < 600):
            say("    %+#06x  f=%12.4f  i=%d" % (o - BAND, v, i))
            shown += 1
            if shown >= 120:
                say("    ...")
                break
    if not shown:
        say("    (nothing in range)")


def main():
    seeds = list(SEEDS)
    for a in sys.argv:
        if a.startswith("--seed="):
            seeds = [int(a.split("=", 1)[1], 0)]
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== p133 seed autopsy %s seeds=%s band=%#x ==="
        % (time.strftime("%H:%M:%S"), [hex(s) for s in seeds], BAND))
    pid = dl.find_pid()
    say("game_pid=%s" % pid)
    if pid is None:
        say("RESULT: game_pid=none")
        say("VERDICT: PARTIAL - game not running (R9)")
        return 3
    try:
        g = gio.Gio(chunk=0x1000)
    except OSError as e:
        say("gio: %s" % e)
        return 2

    first = {}
    for s in seeds:
        lo, b = band(g, s)
        if b:
            first[s] = (lo, b)
    if not first:
        say("RESULT: seeds=0 read")
        say("VERDICT: FAIL - every seed band faulted (freed already?)")
        return 1

    say(">>> mouse: sweep the view left and right for 3 s")
    time.sleep(3)
    second = {s: band(g, s) for s in first}

    hits = 0
    for s in first:
        s_lo, s_b = first[s]
        _t, t_b = second[s]
        say("=== seed %#x" % s)
        def vz(b, o):
            return struct.unpack_from("<fff", b, o)[0:3]
        if t_b and len(t_b) == len(s_b):
            nchg = 0
            for o in range(0, len(s_b) - 11, 4):
                if s_b[o:o + 12] != t_b[o:o + 12]:
                    a, c = vz(s_b, o), vz(t_b, o)
                    d = max(abs(c[0] - a[0]), abs(c[1] - a[1]), abs(c[2] - a[2]))
                    if d > 0.4:
                        yaw_like = all(abs(x) <= 360 for x in (a + c))
                        say("    CHG %+#06x %.3f,%.3f,%.3f -> %.3f,%.3f,%.3f  d=%.2f%s"
                            % (o - BAND, a[0], a[1], a[2], c[0], c[1], c[2], d,
                               "  ANGLE?" if yaw_like else ""))
                        nchg += 1
                        hits += 1
                        if nchg >= 40:
                            say("    ...")
                            break
            if not nchg:
                say("    (no float changed > 0.4)")
        else:
            say("    (second read faulted)")
        dump("f1 %#x" % s, s_lo, s_b)

    say("=== stride walk from %#x" % seeds[0])
    s0 = seeds[0]
    for st in STRIDES:
        row = []
        for k in range(-8, 9):
            b = timed_read(g, s0 + k * st, 12)
            if not b or len(b) < 12:
                row.append("%+d:---" % k)
                continue
            v = struct.unpack_from("<fff", b, 0)
            row.append("%+d:%s" % (k, ("%.0f/%.0f/%.0f" % v) if okT(v)
                                   else ("%.2f/%.2f/%.2f" % v)))
        say("  stride %#x" % st)
        for r in row:
            say("    " + r)

    say("RESULT: seeds=%d changes=%d" % (len(first), hits))
    if hits:
        say("VERDICT: PASS - %d live float changes in the seed bands: angles/fields are there, "
            "read the dump" % hits)
    else:
        say("VERDICT: PARTIAL - seeds read but nothing changed: dump only, no live field")
    return 0


if __name__ == "__main__":
    sys.exit(main())
