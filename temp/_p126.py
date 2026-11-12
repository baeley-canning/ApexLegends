r"""_p126.py -- PROBE p126: the in-match one.  No delta, 0x8000 span, waits for the game.

Copy of p124 with the span opened to 0x8000 and a --wait that blocks until r5apex_dx12
exists, so it can be started BEFORE the match and it samples the live one.

Why it exists: p121's only real read (pos -21.88 26.12 -7705.43, yaw -139.233 pitch 11.146)
was taken at 12:17 with the match still up; every run after the match ended found nothing
plausible at any delta.  The lobby is a different memory state and cannot answer this.

p124 already proved the constraint that matters: with three party names inside 0x100 and a
+-0x3000 window there is no shared world position, so a fixed name-relative offset is dead
for this build.  This probe searches +-0x8000 and only keeps an address that is a plausible
body position for 2+ names at once.
Every probe since p116 assumed one fixed name->position delta and every one of them
collapsed: -0xEEC reads ints-as-floats, -0x10F0 reads zeros, +0xF58 reads code literals
(pos="4.10 0.00 4.10" where pos[0] equals yaw).  So stop asserting a delta.

p121 hit 6/7/8 showed the three party names inside one 30-byte blob, which is a single
roster entry.  If that entry owns one position, then ONE address must be a plausible body
position simultaneously for all three names.  This probe searches the union of the three
windows and keeps only addresses within +-SPAN of every name in the cluster, which is a
structural constraint no single-hit probe can satisfy by accident.

Position filter is deliberately brutal: real map coordinates are hundreds of metres out
(|x| or |z| >= 250), y stays small, and denormals (text/int bytes) are dead.
Read-only, gdrv3 only.  Writes temp\_p126_out.txt, _p126_cand.txt.
RESULT:/VERDICT: name the variable (R5).  Usage: _p126.py [--secs=180] [--wait=900]
"""
import math
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import _p116 as P  # noqa: E402

EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio              # noqa: E402
import dumplive as dl   # noqa: E402

OUT = os.path.join(HERE, "_p126_out.txt")
CAND = os.path.join(HERE, "_p126_cand.txt")
FLOOR = 0x100000000
NEEDLES = ["kern30120", "BurntRice", "BallSharpener"]
SPAN = 0x8000
CLUSTER = 0x100
MIN_XZ = 250.0
YAW_MAX = 360.0


def say(s):
    line = "".join(c if ord(c) < 128 else "?" for c in str(s))
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def pos_ok(v):
    if not all(math.isfinite(c) for c in v):
        return False
    if abs(v[0]) < 1e-20 or abs(v[2]) < 1e-20:      # denormal = pun
        return False
    if max(abs(v[0]), abs(v[2])) < MIN_XZ:
        return False
    if abs(v[1]) > 4000.0 or max(abs(c) for c in v) > 20000.0:
        return False
    return True


def ang_ok(v):
    return (math.isfinite(v[0]) and math.isfinite(v[1])
            and 1e-3 <= abs(v[0]) <= YAW_MAX and abs(v[1]) <= 90.0)



def clusters(hits):
    """Group hits by proximity: one roster entry holds the names ~0xF apart."""
    out = []
    for a, n in sorted(hits):
        if out and a - out[-1][-1][0] <= CLUSTER:
            out[-1].append((a, n))
        else:
            out.append([(a, n)])
    return [c for c in out if len({n for _, n in c}) >= 2]


def scan(g, cl, rlo, rhi, found):
    lo = max(rlo, cl[0][0] - SPAN)
    hi = min(rhi, cl[-1][0] + SPAN + 16)
    try:
        w = dl.retry_phys(g, lo, hi - lo, tries=2)
    except Exception:                                          # noqa: BLE001
        return 0
    nq = len(w) - 16
    pref = None
    hits = 0
    for i in range(0, nq, 4):
        v = struct.unpack("<fff", w[i:i + 12])
        if not pos_ok(v):
            continue
        pa = lo + i
        near = [n for a, n in cl if abs(pa - a) <= SPAN]
        if len(near) < 2:
            continue
        if pref is None:                 # only pay for the angle pass when a pos survives
            pref = [0] * (len(w) + 1)
            for k in range(0, len(w) - 16, 4):
                pref[k + 1] = pref[k] + (
                    1 if ang_ok(struct.unpack("<ff", w[k + 8:k + 16])) else 0)
        alo, ahi = max(0, i - 0x800), min(len(w) - 16, i + 0x800)
        if ahi <= alo or pref[ahi] - pref[alo] == 0:
            continue
        hits += 1
        found.append({"pa": pa, "pos": list(v), "names": sorted(set(near))})
        say("  POS %#x names=%s pos=%.2f %.2f %.2f d_first=%+#x d_last=%+#x"
            % (pa, ",".join(sorted(set(near))), v[0], v[1], v[2],
               pa - cl[0][0], pa - cl[-1][0]))
    return hits


def main():
    secs = 120
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
    for p in (OUT, CAND):
        open(p, "w").close()
    say("=== p124 no-delta intersect %s span=%#x min_xz=%.0f ==="
        % (time.strftime("%H:%M:%S"), SPAN, MIN_XZ))
    pid = dl.find_pid()
    if pid is None and wait > 0:
        say("waiting up to %ds for r5apex_dx12" % wait)
        t = time.time()
        while pid is None and time.time() - t < wait:
            time.sleep(3)
            pid = dl.find_pid()
            if int(time.time() - t) % 15 < 3:
                say("  still waiting (%.0fs)" % (time.time() - t))
        say("wait over after %.0fs, game_pid=%s" % (time.time() - t, pid))
    say("game_pid=%s" % pid)
    if pid is None:
        say("RESULT: game_pid=none")
        say("VERDICT: PARTIAL - game not running (R9)")
        return 3
    try:
        g = gio.Gio(chunk=P.CHUNK)
    except OSError as e:
        say("gio: %s" % e)
        return 2
    ranges, rnote = dl.usable_ranges(g.ram_top, FLOOR, None)
    say("ranges=%d note=%s ram_top=%#x" % (len(ranges), rnote, g.ram_top))
    pats = {n: (n.encode("utf-16-le"), n.encode("ascii")) for n in NEEDLES}
    hits, seen = [], set()
    blocks = 0
    t0 = time.time()
    try:
        for rlo, rhi in ranges:
            pa = (rlo + 7) & ~7
            while pa + P.CHUNK <= rhi and time.time() - t0 < secs and len(hits) < 6000:
                try:
                    blk = dl.retry_phys(g, pa, P.CHUNK, tries=1)
                except OSError:
                    pa += 0x1000
                    continue
                blocks += 1
                for n in NEEDLES:
                    for pat in pats[n]:
                        k = blk.find(pat)
                        while k >= 0 and len(hits) < 6000:
                            a = pa + k
                            k = blk.find(pat, k + 1)
                            if a not in seen:
                                seen.add(a)
                                hits.append((a, n))
                pa += P.CHUNK
                if blocks % 5000 == 0:
                    say("  prog %s blocks=%d hits=%d (%.0fs)"
                        % (time.strftime("%H:%M:%S"), blocks, len(hits), time.time() - t0))
            if time.time() - t0 >= secs or len(hits) >= 6000:
                break
        say("sweep blocks=%d hits=%d (%.1fs)" % (blocks, len(hits), time.time() - t0))
        cls = clusters(hits)
        say("clusters with >=2 names: %d%s"
            % (len(cls), "" if not cls else
               " (sizes %s)" % ",".join(str(len({n for _, n in c})) for c in cls[:20])))
        found = []
        for c in cls[:20]:
            rlo = max(0, c[0][0] - SPAN)
            rhi = min(g.ram_top, c[-1][0] + SPAN + 16)
            say("cluster %#x..%#x names=%s"
                % (c[0][0], c[-1][0], ",".join(sorted({n for _, n in c}))))
            scan(g, c, rlo, rhi, found)
            if any(len(r["names"]) == 3 for r in found):
                say("early exit: a 3-name position exists")
                break
    finally:
        g.close()
    with open(CAND, "w") as f:
        for r in found:
            f.write("%#x names=%s pos=%.3f %.3f %.3f\n"
                    % (r["pa"], ",".join(r["names"]), r["pos"][0], r["pos"][1], r["pos"][2]))
    three = [r for r in found if len(r["names"]) == 3]
    say("RESULT: hits=%d clusters=%d positions=%d with_all3=%d"
        % (len(hits), len(cls), len(found), len(three)))
    if three:
        r = three[0]
        say("VERDICT: PASS - %#x satisfies all three names, pos=%.2f %.2f %.2f"
            % (r["pa"], r["pos"][0], r["pos"][1], r["pos"][2]))
    elif found:
        say("VERDICT: PARTIAL - %d shared positions but none covers all 3 names (%s)"
            % (len(found), found[0]["pa"]))
    else:
        say("VERDICT: FAIL - no plausible position address shared by 2+ names")
    return 0


if __name__ == "__main__":
    sys.exit(main())



