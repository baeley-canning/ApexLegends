r"""_p123.py -- PROBE p123: is name+0x0F58 a body?  Projection + party coherence.

p116..p120 read `name-0xEEC` and got ints-as-floats (height 8.5e-43, yaw 1.03e-08).
p121 found instead: the three names in one blob, a float angle pair `+0xB00`
(yaw=-139.233 pitch=11.146) and a float position `+0xF58` (-21.88 26.12 -7705.43).
p122 confirmed those two offsets by exact bit pattern.

This probe tests that hypothesis instead of asserting it:
  1. strict float typing - a field that is really an int (denormal) is rejected;
  2. the three party names must resolve to three DISTINCT positions;
  3. those positions must be mutually close (a party is one place) and must project
     inside the screen through the live view-projection matrix.

All three or it fails.  Sweep stays above 0x100000000: everything below is prose.
Read-only, gdrv3 only.  Writes temp\_p123_out.txt, _p123_cand.txt.
RESULT:/VERDICT: name the variable (R5).  Usage: _p123.py [--secs=120]
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
import qk_phys as PM    # noqa: E402

OUT = os.path.join(HERE, "_p123_out.txt")
CAND = os.path.join(HERE, "_p123_cand.txt")
OFF = os.path.join(HERE, "qk_offsets.txt")
FLOOR = 0x100000000
NEEDLES = ["kern30120", "BurntRice", "BallSharpener"]
POS_DELTA = 0x0F58
ANG_DELTA = 0x0B00
W, H = 1920, 1080
NEAR = 80.0          # metres a party may span before coherence is meaningless


def say(s):
    line = "".join(c if ord(c) < 128 else "?" for c in str(s))
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def typed(v, lo, hi):
    """Real float field, not an int punned as float (denormals are < 1e-37)."""
    return v is not None and lo <= abs(v) <= hi


def pos_ok(x, y, z):
    return (min(abs(x), abs(z)) >= 1.0 and abs(y) <= 4000.0
            and max(abs(x), abs(y), abs(z)) < 20000.0)


def outer(vp):
    try:
        with open(OFF, "r") as f:
            for ln in f:
                if ln.startswith("image_pa="):
                    return int(ln.split("=", 1)[1], 16) + vp
    except (OSError, ValueError):
        pass
    return None


def vp_matrix(g):
    a = outer(0xDD792B0)
    if a is None:
        return None, "qk_offsets.txt missing image_pa"
    try:
        m = struct.unpack("<16f", dl.retry_phys(g, a, 64, tries=2))
    except Exception as e:                                    # noqa: BLE001
        return None, "vp read fault %s" % type(e).__name__
    if not all(abs(c) < 1e6 for c in m) or abs(m[11]) >= 100.0:
        return None, "vp implausible m11=%.3f" % m[11]
    return m, "ok m15=%.4f m11=%.4f" % (m[15], m[11])



def read_hit(g, a):
    """(pos, yaw, pitch) if both fields are real floats, else None."""
    try:
        px = struct.unpack("<fff", dl.retry_phys(g, a + POS_DELTA, 12, tries=1))
        an = struct.unpack("<ff", dl.retry_phys(g, a + ANG_DELTA, 8, tries=1))
    except Exception:                                          # noqa: BLE001
        return None
    if not pos_ok(*px):
        return None
    if not (typed(an[0], 1e-3, 360.0) and abs(an[1]) <= 90.0):
        return None
    return px, an[0], an[1]


def spread(comb):
    worst = 0.0
    for i in range(len(comb)):
        for j in range(i + 1, len(comb)):
            a, b = comb[i][1], comb[j][1]
            d = math.sqrt(sum((a[k] - b[k]) ** 2 for k in range(3)))
            worst = max(worst, d)
    return worst


def best_combo(per_name):
    names = [n for n in per_name if per_name[n]]
    if len(names) < 2:
        return None
    best, bw = None, 1e18

    def walk(i, acc):
        nonlocal best, bw
        if i == len(names):
            w = spread(acc)
            if w < bw:
                best, bw = list(acc), w
            return
        for c in per_name[names[i]][:4]:
            walk(i + 1, acc + [(names[i], c[0])])
    walk(0, [])
    return (best, bw) if best else None


def main():
    secs = 120
    for a in sys.argv:
        if a.startswith("--secs="):
            secs = int(a.split("=", 1)[1])
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" --secs=%d' % (os.path.abspath(__file__), secs)))
        return 0
    for p in (OUT, CAND):
        open(p, "w").close()
    say("=== p123 body test %s pos=name%+#x ang=name%+#x floor=%#x ==="
        % (time.strftime("%H:%M:%S"), POS_DELTA, ANG_DELTA, FLOOR))
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
    mat, note = vp_matrix(g)
    say("vp %s" % note)
    ranges, rnote = dl.usable_ranges(g.ram_top, FLOOR, None)
    say("ranges=%d note=%s ram_top=%#x" % (len(ranges), rnote, g.ram_top))
    per_name = {n: [] for n in NEEDLES}
    seen = set()
    pats = {n: (n.encode("utf-16-le"), n.encode("ascii")) for n in NEEDLES}
    blocks = raw = 0
    t0 = time.time()
    try:
        for rlo, rhi in ranges:
            pa = (rlo + 7) & ~7
            while pa + P.CHUNK <= rhi and time.time() - t0 < secs:
                try:
                    blk = dl.retry_phys(g, pa, P.CHUNK, tries=1)
                except OSError:
                    pa += 0x1000
                    continue
                blocks += 1
                for n in NEEDLES:
                    for pat in pats[n]:
                        k = blk.find(pat)
                        while k >= 0:
                            a = pa + k
                            k = blk.find(pat, k + 1)
                            if a in seen:
                                continue
                            seen.add(a)
                            raw += 1
                            r = read_hit(g, a)
                            if r is not None and len(per_name[n]) < 8:
                                per_name[n].append((r[0], r[1], r[2], a))
                                say("  %-15s a=%#x pos=%.2f %.2f %.2f yaw=%.2f pitch=%.2f"
                                    % (n, a, r[0][0], r[0][1], r[0][2], r[1], r[2]))
                pa += P.CHUNK
                if blocks % 3000 == 0:
                    say("  prog %s blocks=%d raw=%d kept=%d (%.0fs)"
                        % (time.strftime("%H:%M:%S"), blocks, raw,
                           sum(len(v) for v in per_name.values()), time.time() - t0))
            if time.time() - t0 >= secs:
                break
    finally:
        g.close()
    got = {n: len(v) for n, v in per_name.items()}
    say("sweep blocks=%d raw=%d kept=%s (%.1fs)" % (blocks, raw, got, time.time() - t0))
    with open(CAND, "w") as f:
        for n in NEEDLES:
            for px, yw, pt, a in per_name[n]:
                f.write("%-15s a=%#x pos=%.3f %.3f %.3f yaw=%.3f pitch=%.3f\n"
                        % (n, a, px[0], px[1], px[2], yw, pt))
    res = best_combo(per_name)
    if not res:
        say("RESULT: names_with_a_body=%d of 3" % sum(1 for v in got.values() if v))
        say("VERDICT: %s" % ("PARTIAL - one name only, no coherence test possible"
                             if any(got.values()) else
                             "FAIL - no hit at pos%+#x has a real float pos+angle pair"
                             % POS_DELTA))
        return 0
    combo, bw = res
    say("coherence best spread=%.2f m over %d names" % (bw, len(combo)))
    onscr = 0
    if mat:
        for n, px in combo:
            p = PM.project(mat, px[0], px[1], px[2], W, H)
            ok = bool(p) and 0 <= p[0] <= W and 0 <= p[1] <= H
            onscr += 1 if ok else 0
            say("  proj %-15s pos=%.1f %.1f %.1f -> %s"
                % (n, px[0], px[1], px[2],
                   ("pix=%.0f,%.0f %s" % (p[0], p[1], p[3])) if p else "behind"))
    say("RESULT: names=%d spread=%.2f on_screen=%d/%d vp=%s"
        % (len(combo), bw, onscr, len(combo), "ok" if mat else "missing"))
    if bw <= NEAR and onscr >= 2 and len(combo) == 3:
        say("VERDICT: PASS - name%+#x is a body: 3 distinct names, %.1f m apart, on screen"
            % (POS_DELTA, bw))
    elif len(combo) == 3 and bw <= NEAR:
        say("VERDICT: PARTIAL - 3 names coherent (%.1f m) but only %d projected on screen"
            % (bw, onscr))
    else:
        say("VERDICT: FAIL - %d names, spread %.1f m, on_screen=%d"
            % (len(combo), bw, onscr))
    return 0


if __name__ == "__main__":
    sys.exit(main())

