r"""_p132.py -- PROBE p132: pos-first census.  No names, no typing.

The name family is closed (p124/p126/p130/p131: nothing coordinate-shaped within +-0x3000..0x8000
of any name; three names sit 0xD-0x10 apart = a roster string blob, not a struct).  This probe
stops anchoring on names and finds live PLAYER POSITIONS directly: plausible world triples (the
same ok() filter p124-p131 used) that MOVE when the player walks and go STATIC when the player
stops.  Junk (physics debris, UI floats) moves in every interval or in none.

Three passes over the SAME fixed PA sequence with equal budget, so even a partial sweep is a
valid diff:
    pass1 collect -> "WALK ~20 m" window -> pass2 collect -> diff = moved triples
    -> targeted pass3 re-read of the moved PAs -> still-moving = junk, stopped = walked body
Coherent (same-delta) neighbours within 120 units of a stopped triple = a player record.
PASS prints the seed PAs for p133's autopsy.

Every chunk read is watchdogged (2 s) and a wedged ioctl is skipped and counted (the p130 pass-2
hang must not eat another sitting).  Read-only, gdrv3 only.  Safe to re-run.
Writes temp\_p132_out.txt.  RESULT:/VERDICT: name the variable (R5).
Usage: _p132.py [--budget=90] [--walk=8] [--fmt=float|double|scaled] [--cap=1200]
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

OUT = os.path.join(HERE, "_p132_out.txt")
CHUNK = 0x100000
LO_D = 30.0            # walking-scale displacement, units (covers m and Source units)
HI_D = 4000.0          # bigger than this is a teleport/respawn or a different field
SPAN = 120.0           # cluster radius (squadmate/record width)
LEAK_CAP = 6           # stop sweeping after this many wedged reads


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def pl(v):
    return v == v and 1e-6 < abs(v) < 1e7


def ok(v):
    return (pl(v[0]) and pl(v[1]) and pl(v[2])
            and abs(v[0]) < 12000 and abs(v[1]) < 4000 and abs(v[2]) < 12000
            and (abs(v[0]) > 250 or abs(v[2]) > 250))


def timed_read(g, pa, n, secs=2.0):
    """(buffer|None, wedged).  A wedged ioctl leaks its thread; the caller counts it."""
    box = {}

    def work():
        try:
            box["b"] = dl.retry_phys(g, pa, n, tries=1)
        except Exception:                                       # noqa: BLE001
            pass

    t = threading.Thread(target=work, daemon=True)
    t.start()
    t.join(secs)
    if t.is_alive():
        return None, True
    return box.get("b"), False


def unpack3(b, o, fmt):
    if fmt == "double":
        return struct.unpack_from("<ddd", b, o)
    if fmt == "scaled":
        a = struct.unpack_from("<iii", b, o)
        return (a[0] / 1000.0, a[1] / 1000.0, a[2] / 1000.0)
    return struct.unpack_from("<fff", b, o)


def scan(b, base, fmt, out):
    step = 8 if fmt == "double" else 4
    for o in range(0, len(b) - 3 * step + 1, step):
        v = unpack3(b, o, fmt)
        if ok(v):
            out[base + o] = v


def sweep(g, ranges, budget, fmt, tag):
    hits, swept, leaked, t0 = {}, 0, 0, time.time()
    for rlo, rhi in ranges:
        pa = (rlo + 7) & ~7
        while pa + CHUNK <= rhi:
            if time.time() - t0 > budget or leaked > LEAK_CAP:
                say("  %s aborted t=%.0fs swept=%#x leaked=%d"
                    % (tag, time.time() - t0, swept, leaked))
                return hits, swept
            b, wedge = timed_read(g, pa, CHUNK)
            if wedge:
                leaked += 1
                pa += 0x1000
                continue
            if b:
                scan(b, pa, fmt, hits)
                swept += len(b)
                if (swept >> 20) % 256 < 2:
                    say("  %s %#x %.1f MB/s" % (tag, swept, swept / max(time.time() - t0, 1e-3) / 1e6))
            pa += CHUNK
    say("  %s done t=%.0fs swept=%#x leaked=%d" % (tag, time.time() - t0, swept, leaked))
    return hits, swept


def diff(p1, p2):
    moved = []
    for pa, v2 in p2.items():
        v1 = p1.get(pa)
        if v1 is None:
            continue
        dx, dy, dz = v2[0] - v1[0], v2[1] - v1[1], v2[2] - v1[2]
        d = (dx * dx + dy * dy + dz * dz) ** 0.5
        if LO_D <= d <= HI_D:
            moved.append((pa, v2, (dx, dy, dz), d))
    return moved


def cluster(m):
    """greedy spatial grouping on x/z, big groups first"""
    m = sorted(m, key=lambda e: e[1][0])
    groups = []
    for e in m:
        for c in groups:
            if abs(c[0][1][0] - e[1][0]) <= SPAN and abs(c[0][1][2] - e[1][2]) <= SPAN:
                c.append(e)
                break
        else:
            groups.append([e])
    return sorted(groups, key=len, reverse=True)


def main():
    budget, walk, fmt, cap = 90, 8, "float", 1200
    for a in sys.argv:
        if a.startswith("--budget="):
            budget = int(a.split("=", 1)[1])
        elif a.startswith("--walk="):
            walk = int(a.split("=", 1)[1])
        elif a.startswith("--fmt="):
            fmt = a.split("=", 1)[1]
        elif a.startswith("--cap="):
            cap = int(a.split("=", 1)[1])
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" --budget=%d --walk=%d --fmt=%s --cap=%d'
                            % (os.path.abspath(__file__), budget, walk, fmt, cap)))
        return 0
    open(OUT, "w").close()

    say("=== p132 pos-first census %s fmt=%s budget=%ds walk=%ds cap=%d ==="
        % (time.strftime("%H:%M:%S"), fmt, budget, walk, cap))
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
    total = sum(h - l for l, h in ranges)
    say("ranges=%d note=%s ram_top=%#x total=%#x" % (len(ranges), rnote, g.ram_top, total))

    say(">>> pass1 collecting")
    p1, s1 = sweep(g, ranges, budget, fmt, "p1")
    say("pass1 %s: plausible=%d swept=%#x" % (time.strftime("%H:%M:%S"), len(p1), s1))
    say(">>> WALK ~20 m for the next %ds" % walk)
    time.sleep(walk)
    say(">>> pass2 collecting (keep walking until the STOP line)")
    p2, s2 = sweep(g, ranges, budget, fmt, "p2")
    say("pass2 %s: plausible=%d swept=%#x" % (time.strftime("%H:%M:%S"), len(p2), s2))
    say(">>> STOP walking, stand still")
    time.sleep(1)

    moved = diff(p1, p2)
    say("moved=%d (filter %.0f..%.0f units)" % (len(moved), LO_D, HI_D))
    if not moved:
        say("RESULT: plausible p1=%d p2=%d moved=0 fmt=%s" % (len(p1), len(p2), fmt))
        say("VERDICT: FAIL - no triple moved by a walking delta in this format")
        return 1

    # pass3: is it still moving?  junk keeps moving, the walked body does not.
    still, stop, err = {}, {}, {}
    for pa, v2, _d, _ln in moved[:cap]:
        b, wedge = timed_read(g, pa, 12 + (4 if fmt == "double" else 0))
        if wedge or not b or len(b) < 12:
            err[pa] = 1
            continue
        v3 = unpack3(b, 0, fmt)
        ln = ((v3[0] - v2[0]) ** 2 + (v3[1] - v2[1]) ** 2 + (v3[2] - v2[2]) ** 2) ** 0.5
        (still if ln >= LO_D * 0.3 else stop)[pa] = ln
    say("pass3 over %d: stop=%d still=%d err=%d"
        % (min(len(moved), cap), len(stop), len(still), len(err)))

    groups = cluster(moved)
    say("clusters=%d" % len(groups))
    seeds = 0
    for gi, grp in enumerate(groups[:10]):
        mx = sum(e[2][0] for e in grp) / len(grp)
        my = sum(e[2][1] for e in grp) / len(grp)
        mz = sum(e[2][2] for e in grp) / len(grp)
        say("  c%d n=%d mean=%+.1f,%+.1f,%+.1f" % (gi, len(grp), mx, my, mz))
        for pa, v, d, ln in grp[:8]:
            coh = max(abs(d[0] - mx), abs(d[1] - my), abs(d[2] - mz)) <= 0.25 * max(ln, 1.0)
            st = "STOP" if pa in stop else ("STILL" if pa in still else "ERR")
            say("    @%#011x %10.2f %8.2f %10.2f  d=%+.1f,%+.1f,%+.1f len=%.1f p3=%s%s"
                % (pa, v[0], v[1], v[2], d[0], d[1], d[2], ln, st, " COH" if coh else ""))
            if st == "STOP" and coh and seeds < 24:
                seeds += 1
                say("    SEED %#x" % pa)
        if len(grp) > 8:
            say("    ... %d more" % (len(grp) - 8))

    say("RESULT: fmt=%s moved=%d stop=%d still=%d seeds=%d clusters=%d"
        % (fmt, len(moved), len(stop), len(still), seeds, len(groups)))
    if seeds:
        say("VERDICT: PASS - %d coherent triple(s) walked then stopped: player positions, "
            "now dump the seeds (p133)" % seeds)
        return 0
    say("VERDICT: FAIL - moved triples exist but none is coherent+static: fmt=%s" % fmt)
    return 1


if __name__ == "__main__":
    sys.exit(main())
