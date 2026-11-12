r"""_p120.py -- PROBE p120: kill the prose.  Denormal test + non-zero angles.

p119 found UTF-16 hits everywhere but accepted prose: the 60+ MB of conversation text
sitting in RAM contains all three names, and the bytes that follow a UTF-16 character
decode as DENORMALS (0x0065006b -> 9.4e-39).  A real entity reads a world position
(|x|,|z| >= 0.5, |y| <= 5000) and real angles at name+0x3A4.

Acceptance (all must hold):
    pos finite, no denormals, |x| and |z| >= 0.5, |y| <= 5000
    yaw |y| <= 360, pitch |p| <= 90, at least one of them non-zero
    the 4 bytes at name+0x3AC also finite (guard against a 2-float coincidence)

p119's null result stands as the control: same needles, same ranges, looser test.
Still gdrv3 only.  Writes temp\_p120_out.txt / _p120_neigh.txt / qk_names_live4.json.
RESULT:/VERDICT: name the variable (R5).  Usage: _p120.py [--secs=150]
"""
import json
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
import gio             # noqa: E402
import dumplive as dl  # noqa: E402

OUT = os.path.join(HERE, "_p120_out.txt")
NEI = os.path.join(HERE, "_p120_neigh.txt")
JS = os.path.join(HERE, "qk_names_live4.json")
POS_OFF = 0xEEC
YAW_OFF = 0x3A4
NEEDLES = ["kern30120", "BurntRice", "BallSharpener"]
CAP_PER = 12
WANT_PER = 2


def say(s):
    line = "".join(c if ord(c) < 128 else "?" for c in str(s))
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def entity(g, a, rlo, tag):
    lo = a - POS_OFF
    if lo < rlo:
        return None
    try:
        pb = dl.retry_phys(g, lo, 12, tries=2)
        ab = dl.retry_phys(g, a + YAW_OFF, 12, tries=2)
    except OSError:
        return None
    pv = P.f3(pb)
    if pv is None:
        return None
    if min(abs(pv[0]), abs(pv[2])) < 0.5:          # denormal / prose signature
        return None
    if abs(pv[1]) > 5000.0:                        # height never runs that far
        return None
    an = P.ang(ab[:8])
    if an is None or not (an[0] or an[1]):
        return None
    try:
        tail = struct.unpack("<f", ab[8:12])[0]
    except struct.error:
        return None
    if math.isnan(tail) or math.isinf(tail) or abs(tail) > 20000.0:
        return None
    say("  %-15s a=%#x pos=%.2f %.2f %.2f yaw=%.2f pitch=%.2f t=%.3f ENTITY"
        % (tag, a, pv[0], pv[1], pv[2], an[0], an[1], tail))
    with open(NEI, "a", encoding="utf-8") as f:
        f.write("=== %s a=%#x pos=%s yaw=%.2f pitch=%.2f\n" % (tag, a, pv, an[0], an[1]))
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
    return {"tag": tag, "a": a, "pos": list(pv), "yaw": an[0], "pitch": an[1]}


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
    say("=== p120 anti-prose %s secs=%d ===" % (time.strftime("%H:%M:%S"), secs))
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
    pats = {n: [n.encode("utf-16-le"), n.encode("ascii")] for n in NEEDLES}
    seen = set()
    blocks = fails = tried = 0
    t0 = time.time()
    try:
        for rlo, rhi in ranges:
            pa = (rlo + 0x7) & ~0x7
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
                    for pat, wide in zip(pats[n], (True, False)):
                        pos = 0
                        while len(hits[n]) < CAP_PER:
                            k = blk.find(pat, pos)
                            if k < 0:
                                break
                            a = pa + k
                            pos = k + 1
                            tried += 1
                            h = entity(g, a, rlo, "%s%s" % (n, "16" if wide else "a8"))
                            if not h:
                                continue
                            key = (round(h["pos"][0]), round(h["pos"][1]),
                                   round(h["pos"][2]))
                            if key in seen:
                                say("    (same position, dropped)")
                                continue
                            seen.add(key)
                            hits[n].append(h)
                pa += P.CHUNK
                if blocks % 6000 == 0:
                    say("  prog %s blocks=%d tried=%d ents=%d (%.0fs)"
                        % (time.strftime("%H:%M:%S"), blocks, tried,
                           sum(len(v) for v in hits.values()), time.time() - t0))
                if all(len(hits[n]) >= WANT_PER for n in NEEDLES):
                    break
            if all(len(hits[n]) >= WANT_PER for n in NEEDLES) or time.time() - t0 > secs:
                break
    finally:
        g.close()
    alive = dl.find_pid()
    say("sweep blocks=%d fails=%d tried=%d (%.1fs) game_after=%s"
        % (blocks, fails, tried, time.time() - t0, alive))
    rows = [h for n in NEEDLES for h in hits[n]]
    for n in NEEDLES:
        forms = sorted({"utf16" if r["tag"].endswith("16") else "ascii" for r in hits[n]})
        say("needle %-14s ents=%d forms=%s" % (n, len(hits[n]), forms or "-"))
    got = sum(1 for n in NEEDLES if hits[n])
    say("RESULT: needles_with_entity=%d ents=%d hit_rate=%.4f"
        % (got, len(rows), (len(rows) / tried if tried else 0.0)))
    if rows:
        with open(JS, "w") as f:
            json.dump(rows, f, indent=1)
    if got == len(NEEDLES):
        say("VERDICT: PASS - all 3 names resolve to a positioned, angled object")
    elif got:
        say("VERDICT: PARTIAL - %d of 3 names resolve" % got)
    else:
        say("VERDICT: FAIL - no name resolves to a positioned, angled object")
    if alive is None:
        say("NOTE: game died during the run")
    return 0


if __name__ == "__main__":
    sys.exit(main())
