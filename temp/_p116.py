r"""_p116.py -- PROBE p116: live match, three KNOWN names as needles.

The box is DIRTY (DBUtilDrv2 resident, no reboot) and the game is in a match, so this
is a 1-5 min budget.  It is therefore the *targeted* form of p115: instead of sweeping
for anything entity-shaped, it searches for the three names that are provably in this
match (local `kern30120`, team mates `BurntRice`, `BallSharpener`) and validates each
hit against the entity layout (pos@a-0xEEC finite, angles@a+0x3A4 in yaw/pitch range).

One RAM pass, all three needles at once, early exit when every needle has a validated
hit.  gdrv3 only: no kdu, no apexdrv, no DSE write, nothing to restore (R4 n/a).
Every read stays inside one usable range and `a - POS_OFF` must not fall below it (R10).

Writes temp\_p116_out.txt (log), temp\qk_names_live1.json (table), temp\_p116_neigh.txt
(0x80-byte neighbourhood dumps - the struct past the name is what stage 2 needs).
RESULT:/VERDICT: name the variable (R5).  Usage: _p116.py [--secs=100]
"""
import json
import math
import os
import struct
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio             # noqa: E402
import dumplive as dl  # noqa: E402

OUT = os.path.join(HERE, "_p116_out.txt")
NEI = os.path.join(HERE, "_p116_neigh.txt")
JS = os.path.join(HERE, "qk_names_live1.json")
POS_OFF = 0xEEC
YAW_OFF = 0x3A4
NEEDLES = ["kern30120", "BurntRice", "BallSharpener"]
CAP_PER = 8
CHUNK = 0x10000


def say(s):
    line = "".join(c if ord(c) < 128 else "?" for c in str(s))
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def cap(cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except Exception as e:                      # noqa: BLE001
        return "%r" % e
    txt = " ".join(((p.stdout or "") + (p.stderr or "")).split())
    return txt.replace("SERVICE_NAME:", "")


def f3(blob):
    try:
        v = struct.unpack("<fff", blob)
    except struct.error:
        return None
    for c in v:
        if math.isnan(c) or math.isinf(c) or abs(c) > 20000.0:
            return None
    return v


def ang(blob):
    try:
        y, p = struct.unpack("<ff", blob)
    except struct.error:
        return None
    for c in (y, p):
        if math.isnan(c) or math.isinf(c):
            return None
    if abs(y) > 360.0 or abs(p) > 90.0:
        return None
    return y, p


def check(g, a, rlo, tag):
    """Validate one needle hit; returns a dict or None.  Never reads below rlo."""
    lo = a - POS_OFF
    if lo < rlo:
        return None
    try:
        pb = dl.retry_phys(g, lo, 12, tries=2)
        ab = dl.retry_phys(g, a + YAW_OFF, 8, tries=2)
    except OSError:
        return None
    pv, an = f3(pb), ang(ab)
    if pv is None:
        return None
    if an is None:
        say("  %-14s a=%#x pos=%s angles=BAD -> reject" % (tag, a, pv))
        return None
    say("  %-14s a=%#x pos=%.1f %.1f %.1f yaw=%.2f pitch=%.2f ACCEPT"
        % (tag, a, pv[0], pv[1], pv[2], an[0], an[1]))
    with open(NEI, "a", encoding="utf-8") as f:
        f.write("=== %s a=%#x (pos-%#x, angles+%#x)\n" % (tag, a, POS_OFF, YAW_OFF))
        try:
            blob = dl.retry_phys(g, a - 0x40, 0xC0, tries=2)
        except OSError as e:
            f.write("neighbourhood fault: %s\n" % e)
        else:
            for i in range(0, len(blob), 16):
                pa = a - 0x40 + i
                rel = pa - a
                hx = " ".join("%02x" % b for b in blob[i:i + 16])
                asc = "".join(chr(b) if 0x20 <= b < 0x7F else "." for b in blob[i:i + 16])
                mark = " << name" if rel == 0 else (" <-name" if rel < 0 < rel + 16 else "")
                f.write("  %#x rel=%+#06x %-47s %s%s\n" % (pa, rel, hx, asc, mark))
        f.write("\n")
    return {"tag": tag, "a": a, "pos": list(pv), "yaw": an[0], "pitch": an[1]}



def main():
    secs = 100
    for a in sys.argv:
        if a.startswith("--secs="):
            secs = int(a.split("=", 1)[1])
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" --secs=%d' % (os.path.abspath(__file__), secs)))
        return 0
    for p in (OUT, NEI):
        open(p, "w").close()
    try:
        os.remove(JS)
    except OSError:
        pass
    say("=== p116 live needles %s secs=%d ===" % (time.strftime("%H:%M:%S"), secs))
    say("needles: %s" % NEEDLES)
    pid = dl.find_pid()
    say("game_pid=%s" % pid)
    for svc in ("DBUtilDrv2", "gdrv3", "ApexDrv"):
        say("q[%s] :: %s" % (svc, cap(["sc.exe", "query", svc])[:110]))
    if pid is None:
        say("RESULT: game_pid=none")
        say("VERDICT: PARTIAL - game not running, nothing to read (R9)")
        return 3

    try:
        g = gio.Gio(chunk=CHUNK)
    except OSError as e:
        say("gio: %s" % e)
        return 2
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    say("ranges=%d note=%s ram_top=%#x" % (len(ranges), note, g.ram_top))
    hits = {n: [] for n in NEEDLES}
    bl = {n: n.encode("utf-16-le") for n in NEEDLES}
    ba = {n: n.encode("ascii") for n in NEEDLES}
    blocks = fails = 0
    t0 = time.time()
    done = False
    try:
        for rlo, rhi in ranges:
            pa = (rlo + 0xF) & ~0xF
            while pa + CHUNK <= rhi:
                if done or time.time() - t0 > secs:
                    break
                try:
                    blk = dl.retry_phys(g, pa, CHUNK, tries=1)
                except OSError:
                    fails += 1
                    pa += 0x1000
                    continue
                blocks += 1
                for n in NEEDLES:
                    if len(hits[n]) >= CAP_PER:
                        continue
                    for needle, wide in ((bl[n], True), (ba[n], False)):
                        pos = 0
                        while len(hits[n]) < CAP_PER:
                            k = blk.find(needle, pos)
                            if k < 0:
                                break
                            a = pa + k
                            pos = k + 1
                            if wide and (a & 1 or blk[k - 1:k] == b"\x00"):
                                continue
                            h = check(g, a, rlo, "%s%s" % (n, "16" if wide else "a8"))
                            if h:
                                hits[n].append(h)
                pa += CHUNK
                if blocks % 3000 == 0:
                    say("  prog %s blocks=%d fails=%d found=%d (%.0fs)"
                        % (time.strftime("%H:%M:%S"), blocks, fails,
                           sum(len(v) for v in hits.values()), time.time() - t0))
                done = all(hits[n] for n in NEEDLES)
            if done or time.time() - t0 > secs:
                break
    finally:
        g.close()

    alive = dl.find_pid()
    say("sweep blocks=%d fails=%d (%.1fs) game_after=%s"
        % (blocks, fails, time.time() - t0, alive))
    rows = [h for n in NEEDLES for h in hits[n]]
    for n in NEEDLES:
        say("needle %-14s validated=%d %s"
            % (n, len(hits[n]), "FOUND" if hits[n] else "miss"))
    say("RESULT: needles_found=%d validated=%d of %d"
        % (sum(1 for n in NEEDLES if hits[n]), len(rows), len(NEEDLES)))
    if rows:
        with open(JS, "w") as f:
            json.dump(rows, f, indent=1)
        xs = sorted({round(r["pos"][0]) for r in rows})
        say("distinct X=%d %s" % (len(xs), xs[:12]))
        if len(rows) >= 2:
            say("VERDICT: PASS - %d live entities located by name; layout pos/-%#x and "
                "angles/+%#x hold, neighbours in _p116_neigh.txt"
                % (len(rows), POS_OFF, YAW_OFF))
        else:
            say("VERDICT: PARTIAL - only 1 entity, layout not cross-checked")
    else:
        say("VERDICT: FAIL - 3 known in-match names, no validated hit")
    if alive is None:
        say("NOTE: game died during the run (pid gone) - box was DIRTY")
    return 0


if __name__ == "__main__":
    sys.exit(main())
