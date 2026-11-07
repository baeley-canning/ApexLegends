r"""qk_name.py -- find the player entity by the PLAYER NAME.

This is what every ESP shows and what h320_va.py was built around: the name string is
inside (or pointed at by) the player struct, so a physical scan for it lands on the
entity itself - no DTB, no health-cluster lottery, no offsets guessed.

Scans for the name in UTF-16LE (how the game stores wide strings) and ASCII, then
dumps the neighbourhood of the first few hits so the layout (health / origin / the
pointer to the name) is readable from actual data.

Usage: qk_name.py --needle=kern30120 [--out=FILE] [--show=6] [--span=0x200]
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gio            # noqa: E402
import dumplive as dl  # noqa: E402

ROOT = os.path.dirname(HERE)
TMP = os.path.join(ROOT, "temp")
LOG = []
OUT = None


try:
    import winsound
except ImportError:
    winsound = None


def beep(freq, ms):
    if winsound:
        try:
            winsound.Beep(freq, ms)
        except RuntimeError:
            pass


def set_out(p):
    global OUT
    OUT = os.path.abspath(p) if p else None
    if OUT:
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("")


def out(s):
    line = str(s)
    print(line)
    LOG.append(line)
    if OUT:
        with open(OUT, "a", encoding="utf-8") as f:
            f.write(line + "\n")


def arg(name, default=None, cast=str):
    for i, a in enumerate(sys.argv):
        if a == "--" + name and i + 1 < len(sys.argv):
            return cast(sys.argv[i + 1])
        if a.startswith("--" + name + "="):
            return cast(a.split("=", 1)[1])
    return default


def flag(name):
    return ("--" + name) in sys.argv


def scan(g, ranges, needles):
    hits = []
    n = 0
    for rlo, rhi in ranges:
        pa = (rlo + 7) & ~7
        while pa + 0x10000 <= rhi:
            try:
                blk = dl.retry_phys(g, pa, 0x10000, tries=1)
            except OSError:
                pa += 0x10000
                continue
            n += 1
            for tag, pat in needles:
                i = blk.find(pat)
                while i >= 0:
                    hits.append((pa + i, tag))
                    i = blk.find(pat, i + 1)
            pa += 0x10000
    out("  scanned %d chunks, %d name hits" % (n, len(hits)))
    return hits


def dump(g, lo, span):
    try:
        b = dl.retry_phys(g, lo, span, tries=3)
    except OSError as e:
        out("    dump fault: %s" % e)
        return
    for i in range(0, len(b) - 16, 16):
        q = struct.unpack_from("<QQ", b, i)
        f = struct.unpack_from("<ffff", b, i)
        out("    %#012x  %016X %016X  | %9.2f %9.2f %9.2f %9.2f"
            % (lo + i, q[0], q[1], f[0], f[1], f[2], f[3]))


def main():
    needle = arg("needle", "", cast=str)
    if not needle:
        print("usage: qk_name.py --needle=kern30120")
        return 1
    out_path = arg("out", os.path.join(TMP, "qk_name_%s.txt"
                                      % time.strftime("%Y%m%d_%H%M%S")))
    set_out(out_path)
    if not dl.elevation() and ("--no-elevate" not in sys.argv):
        cmd = " ".join('"%s"' % a if " " in a else a for a in sys.argv) + " --no-elevate"
        out("not elevated - relaunching")
        out(dl.run_elevated(cmd))
        return 0

    out("===== qk_name (find the entity by player name) =====")
    out("needle=%r  out=%s" % (needle, out_path))
    needles = []
    for nm in needle.split(","):
        nm = nm.strip()
        if not nm:
            continue
        needles.append((nm + ":utf16", nm.encode("utf-16-le")))
        needles.append((nm + ":ascii", nm.encode("ascii")))
    out("patterns: %d" % len(needles))
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        out("gio open failed: %s" % e)
        return 2
    try:
        ranges, note = dl.usable_ranges(g.ram_top, None, None)
        out("ranges=%d (%s)" % (len(ranges), note))
        hits = scan(g, ranges, needles)
        if not hits:
            out("RESULT: no-name-hits")
            out("VERDICT: FAIL - the name string is not in RAM (wrong spelling? wrong account?)")
            return 8
        for a, tag in hits[:16]:
            out("  hit %#012x (%s)" % (a, tag))
        show = arg("show", 6, lambda s: int(s, 0))
        span = arg("span", 0x200, lambda s: int(s, 0))
        for a, tag in hits[:show]:
            out("  --- around %#012x (%s) ---" % (a, tag))
            dump(g, a - span // 2, span)

        if flag("layout") and hits:
            n = len(hits)
            idxs = sorted(set([0, n // 5, 2 * n // 5, 3 * n // 5, 4 * n // 5, n - 1]))
            for k in idxs:
                a = hits[k][0]
                lo = a - arg("back", 0x1400, lambda s: int(s, 0))
                ln = arg("len", 0x1600, lambda s: int(s, 0))
                out("  --- block holding name %#x (offset from name) ---" % a)
                try:
                    b = dl.retry_phys(g, lo, ln, tries=3)
                except OSError as e:
                    out("    read fault: %s" % e)
                    continue
                shown = 0
                for i in range(0, len(b) - 12, 4):
                    x, y, z = struct.unpack_from("<fff", b, i)
                    rel = (lo + i) - a
                    if abs(x - 100.0) < 0.05:
                        out("    %+#06x  ~100.0f  (health/shield candidate)")
                        shown += 1
                    elif x == x and max(abs(x), abs(y), abs(z)) > 300.0 and \
                            all(abs(v) < 20000.0 for v in (x, y, z)) and \
                            not all(0 <= v <= 200 for v in (x, y, z)):
                        out("    %+#06x  world-like (%.1f, %.1f, %.1f)" % (rel, x, y, z))
                        shown += 1
                    if shown >= 25:
                        break
            return 0

        if flag("matrix") and hits:
            import qk_phys as P
            W = arg("w", 1920, lambda s: int(s, 0))
            H = arg("h", 1080, lambda s: int(s, 0))
            off = 0xEEC
            origins = []
            for a, tag in hits:
                try:
                    x, y, z = struct.unpack("<fff", dl.retry_phys(g, a - off, 12, tries=1))
                except OSError:
                    continue
                if not all(abs(v) < 20000.0 for v in (x, y, z)):
                    continue
                # the verified player origin had y ~= 2 (ground plane), x/z large
                if abs(y) > 50.0 or max(abs(x), abs(z)) < 300.0:
                    continue
                origins.append((a - off, x, y, z))
            # the verified player stood at y ~= 2.0 exactly; keep only the ground-plane
            # origins, and prefer the ones far from a local origin (the player, not a prop)
            grounded = [o for o in origins if abs(o[2] - 2.0) < 1.0]
            if grounded:
                origins = grounded
            far = [o for o in origins if max(abs(o[1]), abs(o[3])) > 1000.0]
            if far:
                origins = far
            out("  using %d origin(s) (ground plane, far)" % len(origins))
            powner = max(origins, key=lambda o: abs(o[1]) + abs(o[3]))[0] if origins else 0
            others = [o for o in origins if o[0] != powner]
            out("  ground-plane origins at name-0xEEC: %d" % len(origins))
            for o in origins[:8]:
                out("    %#012x (%.1f, %.1f, %.1f)" % o)
            if not origins:
                out("RESULT: no-origins")
                out("VERDICT: PARTIAL - no ground-plane origin among the hits")
                return 8
            # Project DURING the scan: a cap filled with early junk (800) missed the
            # real matrix, so every block is tested as it is found instead.
            out("  scanning RAM and projecting %d origin(s) at 1920x1080..." % len(origins))
            tested = 0
            found = []
            best = []
            views = []
            for cpa, cln in P.chunks(ranges):
                for base, blk in P.scan_chunk(g, cpa, cln):
                    for pat in (P.PONE, P.NONE):
                        i = blk.find(pat)
                        while i >= 0:
                            for start in (i - 60, i - 44):   # m15 (GL) / m11 (D3D)
                                if start < 0 or (start & 3) or start + 64 > len(blk):
                                    continue
                                m = struct.unpack_from("<16f", blk, start)
                                sc = P.score_matrix(m)
                                if not sc:
                                    continue
                                tested += 1
                                # A) view-projection: project to screen centre
                                for opa, x, y, z in origins[:4]:
                                    p = P.project(m, x, y, z, W, H)
                                    if p:
                                        d = ((p[0] - W / 2.0) ** 2 + (p[1] - H / 2.0) ** 2) ** 0.5
                                        best.append((d, base + start, sc, p, opa, (x, y, z)))
                                        best.sort()
                                        del best[12:]
                                # B) VIEW matrix: the camera sits on the player, so the
                                # player's own world position must be ~(0, -eye, 0) in
                                # view space.  A real camera transform is ORTHONORMAL, which
                                # rejects the zero/scale matrices a "small entries" test
                                # accepts (measured: a zero matrix scored 48 and mapped
                                # everything to (0,0,0)).
                                rows = [(m[0], m[1], m[2]), (m[4], m[5], m[6]), (m[8], m[9], m[10])]
                                cols = [(m[0], m[4], m[8]), (m[1], m[5], m[9]), (m[2], m[6], m[10])]
                                def unit(vs):
                                    return all(0.9 < (sum(c * c for c in v)) ** 0.5 < 1.1 for v in vs)
                                # identity rotation = plain translation matrix, which floods
                                # the result (measured: (-387,2,-387) -> (0,2,0)).  A real
                                # camera basis has yaw/pitch, i.e. non-zero off-diagonals.
                                offdiag = any(abs(v) > 0.05 for v in
                                              (m[1], m[2], m[4], m[6], m[8], m[9]))
                                if not ((unit(rows) or unit(cols)) and offdiag):
                                    continue
                                for opa, x, y, z in origins[:4]:
                                    for tag, vx, vy, vz in (
                                        ("row", m[0] * x + m[1] * y + m[2] * z + m[3],
                                                m[4] * x + m[5] * y + m[6] * z + m[7],
                                                m[8] * x + m[9] * y + m[10] * z + m[11]),
                                        ("col", m[0] * x + m[4] * y + m[8] * z + m[12],
                                                m[1] * x + m[5] * y + m[9] * z + m[13],
                                                m[2] * x + m[6] * y + m[10] * z + m[14])):
                                        if opa != powner:
                                            continue
                                        # the PLAYER's own position: eye height below centre
                                        if not (abs(vx) < 60.0 and abs(vz) < 60.0 and -120.0 < vy < -20.0):
                                            continue
                                        # and the OTHER entities must be well away from it,
                                        # which a plain translation matrix cannot satisfy
                                        spread = 0.0
                                        for o2 in others[:3]:
                                            qx = m[0] * o2[1] + m[1] * o2[2] + m[2] * o2[3] + m[3] if tag == "row" else m[0] * o2[1] + m[4] * o2[2] + m[8] * o2[3] + m[12]
                                            qz = m[8] * o2[1] + m[9] * o2[2] + m[10] * o2[3] + m[11] if tag == "row" else m[2] * o2[1] + m[6] * o2[2] + m[10] * o2[3] + m[14]
                                            spread = max(spread, abs(qx) + abs(qz))
                                        if spread < 200.0:
                                            continue
                                        views.append((abs(vx) + abs(vz) + vy, base + start, sc,
                                                      (vx, vy, vz), opa, (x, y, z)))
                                        views.sort()
                                        del views[8:]
                            i = blk.find(pat, i + 4)
                if len(found) >= 8:
                    break
            out("  matrix-shaped blocks tested: %d, VP hits: %d, view hits: %d"
                % (tested, len(best), len(views)))
            for d, mpa, sc, v, opa, org in views[:5]:
                out("    VIEW matrix=%#x score=%d  player in view space = (%.1f, %.1f, %.1f)  d=%.1f  origin=%#x"
                    % (mpa, sc, v[0], v[1], v[2], d, opa))
            if views:
                out("RESULT: view-matrix=%#x origin=%#x" % (views[0][1], views[0][4]))
                out("VERDICT: PASS - the camera sits on the player (view space x,z ~ 0)")
                return 0
            if not best:
                out("RESULT: no-projection")
                out("VERDICT: PARTIAL - no matrix projects the verified origin at all")
                return 8
            out("  closest to screen centre (dx from 960, dy from 540):")
            for d, mpa, sc, p, opa, org in best[:6]:
                out("    matrix=%#x score=%d -> (%4.0f,%4.0f)  d=%5.1f px  origin=%#x (%.1f,%.1f,%.1f) %s"
                    % (mpa, sc, p[0], p[1], d, opa, org[0], org[1], org[2], p[3]))
            bd, bmpa, bsc, bp, bopa, borg = best[0]
            if abs(bp[0] - W / 2.0) <= 0.12 * W and 0.30 * H <= bp[1] <= 0.95 * H:
                out("RESULT: matrix=%#x origin=%#x screen=%.0f,%.0f" % (bmpa, bopa, bp[0], bp[1]))
                out("VERDICT: PASS - the player's own position projects to the screen centre")
                return 0
            out("RESULT: closest=%#x screen=%.0f,%.0f d=%.1f" % (bmpa, bp[0], bp[1], bd))
            out("VERDICT: PARTIAL - no matrix puts the player at the centre (VP assumption)")
            return 0

        if flag("verify") and hits:
            # 1) name-0xEEC must change when the player moves.  2) the same block
            # must hold the ~100.0f health triple.  One run, one movement cue.
            n = len(hits)
            cands = [h[0] for h in hits]          # ALL hits: the entity is 1 of thousands
            out("  candidates: %d" % len(cands))
            off = arg("pos-off", 0xEEC, lambda s: int(s, 0))
            before = {}
            for a in cands:
                try:
                    before[a] = struct.unpack("<fff", dl.retry_phys(g, a - off, 12, tries=2))
                except OSError:
                    before[a] = None
            out("")
            out("  *** RUN IN A CIRCLE for 5 s (beep) ***")
            beep(1300, 250)
            time.sleep(5)
            beep(700, 200)
            survivors = []
            for a in cands:
                b0 = before.get(a)
                try:
                    b1 = struct.unpack("<fff", dl.retry_phys(g, a - off, 12, tries=2))
                except OSError:
                    continue
                if b0 is None:
                    continue
                moved = any(abs(x - y) > 1.0 for x, y in zip(b0, b1))
                world = all(abs(v) < 20000.0 for v in b1) and max(abs(v) for v in b1) > 300.0
                if moved and world:
                    survivors.append((a, b0, b1))
                    out("    MOVED %#x  (%.1f,%.1f,%.1f) -> (%.1f,%.1f,%.1f)"
                        % (a, b0[0], b0[1], b0[2], b1[0], b1[1], b1[2]))
            out("  position-confirmed name hits: %d" % len(survivors))
            if not survivors:
                out("RESULT: position-not-confirmed")
                out("VERDICT: PARTIAL - name-0xEEC did not track movement")
                return 8
            a = survivors[0][0]
            out("  --- health scan inside the confirmed block (%#x, offsets from name) ---" % a)
            lo = a - 0x1500
            b = dl.retry_phys(g, lo, 0x1800, tries=3)
            for i in range(0, len(b) - 12, 4):
                x, y, z = struct.unpack_from("<fff", b, i)
                if abs(x - 100.0) < 0.05 and abs(y - 100.0) < 0.05:
                    out("    %+#06x  (100.0, 100.0, %.1f)  <- health/shield/max triple"
                        % ((lo + i) - a, z))
            out("RESULT: name=%#x origin=%#x" % (a, a - off))
            out("VERDICT: PASS - position tracks the player; health offsets listed above")
            return 0

        if flag("angles") and hits:
            # 1) collect EVERY entity-shaped name hit (entity neighbour is binary, not a
            #    UTF-16 string table), 2) keep the ones whose position drifted over 3 s
            #    of normal play - the player is always among them, a prop rarely is,
            # 3) diff that block for the floats that move = pitch/yaw.
            cands = {}
            for a, tag in hits:
                try:
                    x, y, z = struct.unpack("<fff", dl.retry_phys(g, a - 0xEEC, 12, tries=1))
                    ctx = dl.retry_phys(g, a - 0x30, 0x30, tries=1)
                except OSError:
                    continue
                if not (all(abs(c) < 20000.0 for c in (x, y, z))
                        and max(abs(x), abs(y), abs(z)) > 20.0 and abs(y) < 200.0):
                    continue
                printable = sum(1 for b in ctx if 32 <= b < 127 or b == 0)
                if printable > len(ctx) * 0.8:
                    continue
                cands[a] = (x, y, z)
            out("  entity-shaped candidates: %d" % len(cands))
            if not cands:
                out("RESULT: none")
                out("VERDICT: PARTIAL - every name hit sits in a text table")
                return 8
            time.sleep(3)                                   # passive, no cue
            movers = []
            for a, v0 in cands.items():
                try:
                    v1 = struct.unpack("<fff", dl.retry_phys(g, a - 0xEEC, 12, tries=1))
                except OSError:
                    continue
                d = max(abs(p - q) for p, q in zip(v0, v1))
                if d > 0.5:
                    movers.append((d, a, v0, v1))
            out("  candidates that drifted in 3 s: %d" % len(movers))
            for d, a, v0, v1 in sorted(movers, reverse=True)[:6]:
                out("    %#012x (%.1f,%.1f,%.1f) -> (%.1f,%.1f,%.1f)  d=%.1f"
                    % (a, v0[0], v0[1], v0[2], v1[0], v1[1], v1[2], d))
            if not movers:
                out("RESULT: nothing drifted")
                out("VERDICT: PARTIAL - no candidate moved (stand still is fine, but nothing drifted)")
                return 8
            ent = sorted(movers, reverse=True)[0][1]
            out("  player entity = %#012x (origin %#x)" % (ent, ent - 0xEEC))
            lo = ent - 0x1600
            ln = 0x1A00
            try:
                b0 = dl.retry_phys(g, lo, ln, tries=3)
                time.sleep(3)
                b1 = dl.retry_phys(g, lo, ln, tries=3)
            except OSError:
                out("RESULT: block unreadable")
                return 5
            out("  floats that changed (offset from name, old -> new):")
            nch = 0
            for i in range(0, min(len(b0), len(b1)) - 4, 4):
                x0 = struct.unpack_from("<f", b0, i)[0]
                x1 = struct.unpack_from("<f", b1, i)[0]
                if x0 == x1 or x1 != x1 or x0 != x0:
                    continue
                if abs(x1) > 1000.0 or abs(x0) > 1000.0:
                    continue
                out("    %+#06x  %10.3f -> %10.3f" % ((lo + i) - ent, x0, x1))
                nch += 1
            out("RESULT: player=%#x changed=%d" % (ent, nch))
            out("VERDICT: PASS - player identified; angle candidates dumped")
            return 0

        if flag("probe"):
            # Treat the name as inline at entity+0x10F0 (the old h320_va set) and ask
            # whether the health field at +0x5E0 reads plausibly.  One read per hit.
            out("  --- probing entity layout: base = hit-0x10F0, hp@base+0x5E0 ---")
            good = 0
            for a, tag in hits:
                base = a - 0x10F0
                if base < 0x1000:
                    continue
                try:
                    b = dl.retry_phys(g, base + 0x5E0, 16, tries=1)
                except OSError:
                    continue
                hp, sh, t2, alive = struct.unpack("<iiii", b)
                if not (0 <= hp <= 200) or not (0 <= sh <= 200):
                    continue
                try:
                    o = dl.retry_phys(g, base + 0x330, 12, tries=1)
                except OSError:
                    continue
                x, y, z = struct.unpack("<fff", o)
                if not all(v == v and abs(v) < 20000.0 for v in (x, y, z)):
                    continue
                good += 1
                out("    base=%#012x name=%#x hp=%d shield=%d t2=%d alive=%d origin=(%.1f, %.1f, %.1f)"
                    % (base, a, hp, sh, t2, alive, x, y, z))
                if good >= 12:
                    break
            out("  entity-shaped hits: %d" % good)

        out("RESULT: hits=%d first=%#x" % (len(hits), hits[0][0]))
        out("VERDICT: PASS - name located in RAM")
        return 0
    finally:
        try:
            g.close()
        except Exception:                        # noqa: BLE001
            pass


if __name__ == "__main__":
    sys.exit(main())
