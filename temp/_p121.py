r"""_p121.py -- PROBE p121: stop guessing the delta, measure it.

p116..p120 all hardcoded pos = name - 0xEEC.  p120 proves that lands in a near-zero
struct (pos="2.13 0.00 2.13", yaw=pitch=0.00) on every accepted hit, so -0xEEC is stale.
Two candidate anchors exist in the repo (-0xEEC from qk_esp, -0x10F0 from qk_name3),
which is exactly the signature of a build that moved.

This probe takes each raw name hit, reads a +-0x2000 window around it, and reports every
offset that reads a position with plausible angles within +-0x800 of it.  The delta
becomes output, not input.

Two hard rules taken from the proven qk_esp path:
  * floor 0x100000000 - the real name strings live in the game heap above 4 GB; every
    byte below that is conversation prose, personas and script source (p119/p120).
  * angles must be sane AND non-zero; a null qword at the wrong delta reads 0.00.

Read-only, gdrv3 only.  Writes temp\_p121_out.txt, _p121_cand.txt, qk_delta.json.
RESULT:/VERDICT: name the variable (R5).  Usage: _p121.py [--hits=40] [--secs=140]
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

OUT = os.path.join(HERE, "_p121_out.txt")
CAND = os.path.join(HERE, "_p121_cand.txt")
JS = os.path.join(HERE, "qk_delta.json")
FLOOR = 0x100000000
NEEDLES = ["kern30120", "BurntRice", "BallSharpener"]
SPAN = 0x2000
YAW_OFF = 0x3A4
ANG_WIN = 0x800


def say(s):
    line = "".join(c if ord(c) < 128 else "?" for c in str(s))
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def good_pos(pv):
    if pv is None:
        return False
    for c in pv:
        if math.isnan(c) or math.isinf(c):
            return False
    if min(abs(pv[0]), abs(pv[2])) < 0.5:      # denormal = text bytes
        return False
    if abs(pv[1]) > 4000.0:
        return False
    return True


def good_ang(an):
    if an is None or not (an[0] or an[1]):
        return False
    return abs(an[0]) <= 360.0 and abs(an[1]) <= 90.0


def probe(g, hit, rlo, rhi, tag, out):
    lo = max(rlo, hit - SPAN)
    hi = min(rhi, hit + SPAN + YAW_OFF + ANG_WIN + 12)
    try:
        w = dl.retry_phys(g, lo, hi - lo, tries=2)
    except OSError:
        return 0
    base = hit - lo
    nq = len(w) - 12
    # one pass: which qword offsets read sane, non-zero angles with a finite tail
    ang_ok = bytearray(max(0, nq))
    for i in range(0, nq, 4):
        an = P.ang(w[i:i + 8])
        if not good_ang(an):
            continue
        tail = struct.unpack("<f", w[i + 8:i + 12])[0]
        if math.isnan(tail) or math.isinf(tail) or abs(tail) > 20000.0:
            continue
        ang_ok[i] = 1
    pref = [0] * (len(ang_ok) + 1)
    for i in range(len(ang_ok)):
        pref[i + 1] = pref[i] + ang_ok[i]
    found = 0
    for off in range(-SPAN, SPAN + 1, 4):
        i = base + off
        if i < 0 or i + 12 > len(w):
            continue
        pv = P.f3(w[i:i + 12])
        if not good_pos(pv):
            continue
        alo = max(0, i + YAW_OFF - ANG_WIN)
        ahi = min(len(ang_ok), i + YAW_OFF + ANG_WIN + 1)
        if ahi <= alo or pref[ahi] - pref[alo] == 0:
            continue
        j = alo + ang_ok.find(1, alo) if alo < len(ang_ok) else -1
        if j < 0 or j >= ahi:
            j = next((k for k in range(alo, ahi) if ang_ok[k]), -1)
        if j < 0:
            continue
        an = P.ang(w[j:j + 8])
        tail = struct.unpack("<f", w[j + 8:j + 12])[0]
        rec = {"tag": tag, "hit": hit, "delta": off, "pos": list(pv),
               "yaw": an[0], "pitch": an[1], "t": tail}
        out.append(rec)
        say("  cand %-15s hit=%#x delta=%+#07x pos=%.2f %.2f %.2f yaw=%.2f pitch=%.2f"
            % (tag, hit, off, pv[0], pv[1], pv[2], an[0], an[1]))
        found += 1
    return found


def main():
    hits_n, secs = 40, 140
    for a in sys.argv:
        if a.startswith("--hits="):
            hits_n = int(a.split("=", 1)[1])
        elif a.startswith("--secs="):
            secs = int(a.split("=", 1)[1])
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" --hits=%d --secs=%d'
                            % (os.path.abspath(__file__), hits_n, secs)))
        return 0
    for p in (OUT, CAND):
        open(p, "w").close()
    say("=== p121 delta discovery %s hits=%d secs=%d floor=%#x ==="
        % (time.strftime("%H:%M:%S"), hits_n, secs, FLOOR))
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
    ranges, note = dl.usable_ranges(g.ram_top, FLOOR, None)
    say("ranges=%d note=%s ram_top=%#x" % (len(ranges), note, g.ram_top))
    if not ranges:
        g.close()
        say("RESULT: ranges=0")
        say("VERDICT: FAIL - nothing above floor")
        return 4
    pats = {n: [n.encode("utf-16-le"), n.encode("ascii")] for n in NEEDLES}
    hit_cap = {n: 0 for n in NEEDLES}
    per = max(1, hits_n // len(NEEDLES))
    cands = []
    seen_hit = set()
    blocks = fails = raw = 0
    t0 = time.time()
    try:
        for rlo, rhi in ranges:
            pa = (rlo + 0x7) & ~0x7
            while pa + P.CHUNK <= rhi:
                if time.time() - t0 > secs or raw >= hits_n:
                    break
                try:
                    blk = dl.retry_phys(g, pa, P.CHUNK, tries=1)
                except OSError:
                    fails += 1
                    pa += 0x1000
                    continue
                blocks += 1
                for n in NEEDLES:
                    if hit_cap[n] >= per:
                        continue
                    for pat, wide in zip(pats[n], (True, False)):
                        pos = 0
                        while hit_cap[n] < per and raw < hits_n:
                            k = blk.find(pat, pos)
                            if k < 0:
                                break
                            a = pa + k
                            pos = k + 1
                            if a in seen_hit:
                                continue
                            seen_hit.add(a)
                            raw += 1
                            hit_cap[n] += 1
                            say("hit %d %-15s a=%#x"
                                % (raw, "%s%s" % (n, "16" if wide else "a8"), a))
                            try:
                                probe(g, a, rlo, rhi,
                                      "%s%s" % (n, "16" if wide else "a8"), cands)
                            except OSError as e:
                                say("  probe fault %s" % e)
                pa += P.CHUNK
                if blocks % 4000 == 0:
                    say("  prog %s blocks=%d raw=%d cand=%d (%.0fs)"
                        % (time.strftime("%H:%M:%S"), blocks, raw, len(cands),
                           time.time() - t0))
                if raw >= hits_n:
                    break
            if raw >= hits_n or time.time() - t0 > secs:
                break
    finally:
        g.close()
    alive = dl.find_pid()
    say("sweep blocks=%d fails=%d raw_hits=%d cand=%d (%.1fs) game_after=%s"
        % (blocks, fails, raw, len(cands), time.time() - t0, alive))
    with open(CAND, "w") as f:
        for i, r in enumerate(cands):
            f.write("%02d %-15s hit=%#x delta=%+#07x pos=%.2f %.2f %.2f yaw=%.2f pitch=%.2f\n"
                    % (i, r["tag"], r["hit"], r["delta"], r["pos"][0], r["pos"][1],
                       r["pos"][2], r["yaw"], r["pitch"]))
    hist = {}
    for r in cands:
        hist[r["delta"]] = hist.get(r["delta"], 0) + 1
    top = sorted(hist.items(), key=lambda kv: -kv[1])[:6]
    say("RESULT: raw_hits=%d cand=%d distinct_deltas=%d top=%s"
        % (raw, len(cands), len(hist),
           " ".join("%+#07x:%d" % (d, c) for d, c in top)))
    tags = {r["tag"][:-2] for r in cands}
    if cands:
        with open(JS, "w") as f:
            json.dump(cands, f, indent=1)
    if top and top[0][1] >= 3:
        say("VERDICT: PASS - delta %+#07x recurs %d times; anchor is measurable"
            % (top[0][0], top[0][1]))
    elif cands:
        say("VERDICT: PARTIAL - %d candidates across %d names, no repeating delta"
            % (len(cands), len(tags)))
    else:
        say("VERDICT: FAIL - no offset in +-%#x of any name hit reads pos+angles" % SPAN)
    if alive is None:
        say("NOTE: game died during the run")
    return 0


if __name__ == "__main__":
    sys.exit(main())

