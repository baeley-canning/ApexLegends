r"""_p117.py -- PROBE p117: p116 with STRICT acceptance and no early exit.

p116 exited after 3.5 s / ~470 MB because `(0,0,0)` is "finite", so the first junk hit
on each needle satisfied `done`.  One variable changed here: what counts as an entity.

  strict: pos finite AND at least one |component| >= 100 AND not a zero XZ pair
          (world coordinates are thousands; a 0,0,0 triple is a zeroed struct)
  no early exit until every needle holds a strict hit; hard cap --secs.
  UTF-16 and ASCII both tried; the form that wins is logged, because p116 found
  ASCII copies only and qk_esp reads UTF-16 - that discrepancy has to be measured.

gdrv3 only, no kdu, no apexdrv, nothing to restore.  Reads stay inside one range (R10).
Writes temp\_p117_out.txt, temp\_p117_neigh.txt, temp\qk_names_live2.json.
RESULT:/VERDICT: name the variable (R5).  Usage: _p117.py [--secs=150]
"""
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import _p116 as P  # noqa: E402

EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio             # noqa: E402
import dumplive as dl  # noqa: E402

OUT = os.path.join(HERE, "_p117_out.txt")
NEI = os.path.join(HERE, "_p117_neigh.txt")
JS = os.path.join(HERE, "qk_names_live2.json")
POS_OFF = 0xEEC
YAW_OFF = 0x3A4
NEEDLES = ["kern30120", "BurntRice", "BallSharpener"]
CAP_PER = 6


def say(s):
    line = "".join(c if ord(c) < 128 else "?" for c in str(s))
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def strict(g, a, rlo, tag):
    lo = a - POS_OFF
    if lo < rlo:
        return None
    try:
        pb = dl.retry_phys(g, lo, 12, tries=2)
    except OSError:
        return None
    pv = P.f3(pb)
    if pv is None:
        return None
    if max(abs(pv[0]), abs(pv[1]), abs(pv[2])) < 100.0:
        return None
    if abs(pv[0]) < 1.0 and abs(pv[2]) < 1.0:
        return None
    try:
        an = P.ang(dl.retry_phys(g, a + YAW_OFF, 8, tries=2))
    except OSError:
        an = None
    say("  %-15s a=%#x pos=%.1f %.1f %.1f ang=%s STRICT"
        % (tag, a, pv[0], pv[1], pv[2],
           ("%.1f/%.1f" % an) if an else "BAD"))
    with open(NEI, "a", encoding="utf-8") as f:
        f.write("=== %s a=%#x\n" % (tag, a))
        try:
            blob = dl.retry_phys(g, a - 0x40, 0xC0, tries=2)
        except OSError as e:
            f.write("fault %s\n" % e)
        else:
            for i in range(0, len(blob), 16):
                rel = (a - 0x40 + i) - a
                hx = " ".join("%02x" % b for b in blob[i:i + 16])
                asc = "".join(chr(b) if 0x20 <= b < 0x7F else "." for b in blob[i:i + 16])
                f.write("  rel=%+#06x %-47s %s%s\n"
                        % (rel, hx, asc, " << name" if rel == 0 else ""))
        f.write("\n")
    return {"tag": tag, "a": a, "pos": list(pv),
            "yaw": an[0] if an else None, "pitch": an[1] if an else None}


def main():
    secs = 150
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
    say("=== p117 strict %s secs=%d ===" % (time.strftime("%H:%M:%S"), secs))
    pid = dl.find_pid()
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
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    say("ranges=%d note=%s ram_top=%#x" % (len(ranges), note, g.ram_top))
    hits = {n: [] for n in NEEDLES}
    bl = {n: n.encode("utf-16-le") for n in NEEDLES}
    ba = {n: n.encode("ascii") for n in NEEDLES}
    blocks = fails = 0
    t0 = time.time()
    try:
        for rlo, rhi in ranges:
            pa = (rlo + 0xF) & ~0xF
            while pa + P.CHUNK <= rhi:
                if time.time() - t0 > secs:
                    break
                try:
                    blk = dl.retry_phys(g, pa, P.CHUNK, tries=1)
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
                            h = strict(g, a, rlo, "%s%s" % (n, "16" if wide else "a8"))
                            if h:
                                hits[n].append(h)
                pa += P.CHUNK
                if blocks % 3000 == 0:
                    say("  prog %s blocks=%d fails=%d strict=%d (%.0fs)"
                        % (time.strftime("%H:%M:%S"), blocks, fails,
                           sum(len(v) for v in hits.values()), time.time() - t0))
                if all(hits[n] for n in NEEDLES):
                    break
            if all(hits[n] for n in NEEDLES) or time.time() - t0 > secs:
                break
    finally:
        g.close()
    alive = dl.find_pid()
    say("sweep blocks=%d fails=%d (%.1fs) game_after=%s"
        % (blocks, fails, time.time() - t0, alive))
    rows = [h for n in NEEDLES for h in hits[n]]
    for n in NEEDLES:
        forms = sorted({"utf16" if r["tag"].endswith("16") else "ascii" for r in hits[n]})
        say("needle %-14s strict=%d forms=%s" % (n, len(hits[n]), forms or "-"))
    got = sum(1 for n in NEEDLES if hits[n])
    say("RESULT: needles_strict=%d strict_hits=%d blocks=%d"
        % (got, len(rows), blocks))
    if rows:
        with open(JS, "w") as f:
            json.dump(rows, f, indent=1)
    if got >= 2:
        say("VERDICT: PASS - %d of 3 names carry world positions with |c|>=100" % got)
    elif got == 1:
        say("VERDICT: PARTIAL - one name only; layout not cross-checked")
    else:
        say("VERDICT: FAIL - no name carries a world position")
    if alive is None:
        say("NOTE: game died during the run")
    return 0


if __name__ == "__main__":
    sys.exit(main())

