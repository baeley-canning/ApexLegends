r"""qk_phys.py -- find ESP data with PHYSICAL reads only.  No DTB, no driver.

Why: the translator cost us the whole night (apexdrv presence is fatal to the game;
the driver-free DTB scan is slow and unproven).  Physical pages do not move while a
process lives, so each address is resolved ONCE, cached, and re-read at frame rate.

Three things are found by shape and then validated against each other:

  1. HEALTH : aligned 100.0f, >= 3 within 0x80 (health / max / shield), still there
              after a gap.  p62/p64 proved this shape works on this box.
  2. ORIGIN : near a health cluster, a 3-float world position (finite, |v| 50..20000).
  3. MATRIX : a 64-byte block ending in +-1.0f that passes a strict view-projection
              test.  Prefiltered on the +-1.0f, because a 4-byte-stride scan of
              27 GB is impossible in Python.

The validation is the point: a matrix that projects the found origin to a sane
screen coordinate with w > 0 is *the* matrix, not a lookalike.

Usage:
  qk_phys.py --find [--out=FILE] [--w=2560] [--h=1440] [--max-matrix=400]
  qk_phys.py --dump --pa=0xADDR --len=256
Exit: 0 found, 8 nothing found, 2 no transport.
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

CHUNK = 0x10000
F100 = b"\x00\x00\xc8\x42"          # 100.0f
PONE = b"\x00\x00\x80\x3f"          # +1.0f
NONE = b"\x00\x00\x80\xbf"          # -1.0f


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


class Ram(object):
    def __init__(self, ranges):
        self.r = sorted(ranges)

    def ok(self, pa, n=1):
        for a, b in self.r:
            if a <= pa and pa + n <= b:
                return True
        return False


def chunks(ranges, chunk=CHUNK):
    for rlo, rhi in ranges:
        pa = (rlo + 7) & ~7
        while pa + chunk <= rhi:
            yield pa, chunk
            pa += chunk


def scan_chunk(g, pa, ln):
    """(pa, bytes) for each readable piece of [pa, pa+ln).

    A 64 KiB read dies if ANY page inside it is unbacked (25 bad intervals on this
    box), so a failed block is re-read page by page - a bad page costs one page,
    not the block.
    """
    try:
        yield pa, dl.retry_phys(g, pa, ln, tries=1)
        return
    except OSError:
        pass
    for off in range(0, ln, 0x1000):
        try:
            yield pa + off, dl.retry_phys(g, pa + off, 0x1000, tries=1)
        except OSError:
            continue


def find_health(g, ranges, want=24):
    """Clusters of aligned 100.0f: (pa, [member offsets within 0x80])."""
    hits = []
    n = 0
    for pa, ln in chunks(ranges):
        n += 1
        if (n & 0x3FFF) == 0:
            out("    health: %d chunks, %d raw hits" % (n, len(hits)))
        for base, blk in scan_chunk(g, pa, ln):
            i = blk.find(F100)
            while i >= 0:
                if (i & 3) == 0:
                    hits.append(base + i)
                i = blk.find(F100, i + 1)
        if len(hits) > 200000:
            break
    out("  raw 100.0f hits: %d (%d chunks)" % (len(hits), n))
    hits.sort()
    clusters = []
    for k, a in enumerate(hits):
        mem = [h - a for h in hits[k:k + 8] if 0 <= h - a <= 0x80]
        if len(mem) >= 3:
            clusters.append((a, mem))
    out("  health clusters: %d" % len(clusters))
    return clusters[:want]


def settle(g, ram, clusters, gap=1.5):
    """Keep clusters that still hold a 100.0f member after a gap.

    Requiring EVERY member to survive rejected all 24,462 clusters in the range (one
    churning value dropped the whole entity), and the function then lost its return
    entirely.  One live member is enough - the projection test is the real filter.
    """
    if not clusters:
        return []
    time.sleep(gap)
    kept = []
    for base, mem in clusters:
        live = 0
        for off in mem:
            try:
                b = dl.retry_phys(g, base + off, 4, tries=2)
            except OSError:
                continue
            if struct.unpack("<f", b)[0] == 100.0:
                live += 1
        if live:
            kept.append((base, mem))
    out("  clusters with a live 100.0f after %.1fs: %d" % (gap, len(kept)))
    return kept

# ---------------------------------------------------------------- 2. origin
def find_origin(g, ram, base, back=0x400, fwd=0x900):
    """A 3-float WORLD position near a health cluster.

    The first version accepted any triple with two components in 50..20000, so it
    kept returning the health triple itself (100.0, 100.0, 50.0).  A world position
    has at least one component in the hundreds-to-thousands, and is not a small
    all-health-looking triple.
    """
    lo = base - back if base > back else 0
    try:
        buf = dl.retry_phys(g, lo, back + fwd, tries=3)
    except OSError:
        return None
    best = None
    for off in range(0, len(buf) - 12, 4):
        x, y, z = struct.unpack_from("<fff", buf, off)
        if x != x or y != y or z != z:
            continue
        if abs(x) > 20000.0 or abs(y) > 20000.0 or abs(z) > 20000.0:
            continue
        if x == 0.0 and y == 0.0 and z == 0.0:
            continue
        biggest = max(abs(x), abs(y), abs(z))
        if biggest < 300.0:                       # world coordinates are large
            continue
        if all(0.0 <= v <= 200.0 for v in (x, y, z)):   # health-looking triple
            continue
        score = 2 + (1 if biggest > 1000.0 else 0) + (1 if len(set((x, y, z))) == 3 else 0)
        if best is None or score > best[0]:
            best = (score, lo + off, x, y, z)
    return best


# ---------------------------------------------------------------- 3. matrix
def score_matrix(m):
    """View-projection in EITHER convention.

    D3D-style row-major VP has m[11] = -1 and m[15] = 0, so a prefilter on +-1 at
    the END of the block (m15) only ever sees projection-less or identity-ish
    blocks.  Accept +-1 at m15 (column-vector GL style) OR at m11 (D3D style).
    """
    for v in m:
        if v != v or abs(v) > 1.0e5:
            return 0
    if not (abs(abs(m[15]) - 1.0) < 0.01 or abs(abs(m[11]) - 1.0) < 0.01):
        return 0
    small = 0
    for i in (0, 1, 2, 4, 5, 6, 8, 9, 10):
        if abs(m[i]) <= 2.0:
            small += 1
    if small < 6:
        return 0
    if not any(100.0 < abs(m[i]) < 1.0e5 for i in (12, 13, 14, 3, 7, 11)):
        return 0
    return 30 + small * 2


def find_matrices(g, ranges, cap=400):
    """64-byte blocks ending in +-1.0f that look like a view-projection."""
    found = []
    n = 0
    for pa, ln in chunks(ranges):
        n += 1
        if (n & 0x3FFF) == 0:
            out("    matrix: %d chunks, %d candidates" % (n, len(found)))
        for base, blk in scan_chunk(g, pa, ln):
            for pat in (PONE, NONE):
                i = blk.find(pat)
                while i >= 0:
                    start = i - 60                 # m15 sits at +0x3C of the block
                    if start >= 0 and (start & 3) == 0:
                        m = struct.unpack_from("<16f", blk, start)
                        sc = score_matrix(m)
                        if sc:
                            found.append((sc, base + start, m))
                            if len(found) >= cap:
                                return found
                    i = blk.find(pat, i + 4)
    out("  matrix candidates: %d (%d chunks)" % (len(found), n))
    return found


def project(m, x, y, z, w, h):
    """World -> pixel, trying both conventions.  Returns (sx, sy, wv, tag)."""
    cands = []
    cx = m[0] * x + m[4] * y + m[8] * z + m[12]      # column-vector: p' = M p
    cy = m[1] * x + m[5] * y + m[9] * z + m[13]
    cw = m[3] * x + m[7] * y + m[11] * z + m[15]
    cands.append((cx, cy, cw, "col"))
    rx = m[0] * x + m[1] * y + m[2] * z + m[3]        # row-vector: p' = p M
    ry = m[4] * x + m[5] * y + m[6] * z + m[7]
    rw = m[12] * x + m[13] * y + m[14] * z + m[15]
    cands.append((rx, ry, rw, "row"))
    for cx, cy, cw, tag in cands:
        if cw <= 1e-6:
            continue
        sx = (cx / cw * 0.5 + 0.5) * w
        sy = (0.5 - cy / cw * 0.5) * h
        return sx, sy, cw, tag                     # cw = view depth (for box size)
    return None


def main():
    out_path = arg("out", os.path.join(TMP, "qk_phys_%s.txt" % time.strftime("%Y%m%d_%H%M%S")))
    set_out(out_path)
    if not dl.elevation() and not flag("no-elevate"):
        cmd = " ".join('"%s"' % a if " " in a else a for a in sys.argv) + " --no-elevate"
        out("not elevated - relaunching")
        out(dl.run_elevated(cmd))
        return 0

    out("===== qk_phys (physical ESP finder: health -> origin -> matrix) =====")
    out("out=%s" % out_path)
    try:
        # chunk=64 KiB: gio splits a read into self.chunk pieces, so the default 4 KiB
        # landing buffer would turn every 64 KiB block into 16 ioctls (25 min a pass).
        g = gio.Gio(chunk=CHUNK)
    except OSError as e:
        out("gio open failed: %s" % e)
        out("VERDICT: PARTIAL - no transport")
        return 2

    try:
        if flag("dump"):
            pa = arg("pa", 0, lambda s: int(s, 0))
            ln = arg("len", 256, lambda s: int(s, 0))
            b = dl.retry_phys(g, pa, ln, tries=4)
            for i in range(0, len(b) - 12, 4):
                x, y, z = struct.unpack_from("<fff", b, i)
                sane = all(v == v and abs(v) < 1e6 for v in (x, y, z))
                out("  %#012x  %12.4f %12.4f %12.4f   %s"
                    % (pa + i, x, y, z,
                       ("<-- world-like" if sane and max(abs(x), abs(y), abs(z)) > 300.0
                        and not all(0 <= v <= 200.0 for v in (x, y, z)) else "")))
            return 0

        ranges, note = dl.usable_ranges(g.ram_top, None, None)
        ram = Ram(ranges)
        out("ram_top=%#x ranges=%d (%s) usable=%.1f GB"
            % (g.ram_top, len(ranges), note,
               sum(b - a for a, b in ranges) / 1073741824.0))

        W = arg("w", 2560, lambda s: int(s, 0))
        H = arg("h", 1440, lambda s: int(s, 0))
        out("screen assumption %dx%d (pass --w/--h to match)" % (W, H))

        t0 = time.perf_counter()
        clusters = find_health(g, ranges)
        clusters.sort(key=lambda c: -len(c[1]))
        out("  densest clusters kept for the origin stage: %d" % min(40, len(clusters)))
        clusters = settle(g, ram, clusters[:40])
        out("  health scan %.1fs" % (time.perf_counter() - t0))
        if not clusters:
            out("RESULT: no-health")
            out("VERDICT: PARTIAL - no stable 100.0f cluster (not in a match?)")
            return 8

        origins = []
        for base, mem in clusters[:8]:
            o = find_origin(g, ram, base)
            if o:
                origins.append(o)
                out("  origin near %#x: at %#x (%.1f, %.1f, %.1f) score=%d"
                    % (base, o[1], o[2], o[3], o[4], o[0]))

        if flag("dump-near") and clusters:
            base = clusters[0][0]
            lo = base - 0x400 if base > 0x400 else 0
            out("  --- dump around live cluster %#x (members %s) ---"
                % (base, ",".join("%#x" % (base + m) for m in clusters[0][1])))
            b = dl.retry_phys(g, lo, 0xC00, tries=4)
            for i in range(0, len(b) - 12, 4):
                x, y, z = struct.unpack_from("<fff", b, i)
                if x != x or y != y or z != z:
                    continue
                if all(v == 0.0 for v in (x, y, z)):
                    continue
                tag = ""
                if max(abs(x), abs(y), abs(z)) > 300.0:
                    tag = "<-- world-like"
                out("  %#012x  %12.4f %12.4f %12.4f  %s" % (lo + i, x, y, z, tag))
            return 0
        if not origins:
            out("RESULT: no-origin")
            out("VERDICT: PARTIAL - health found, no position near it")
            return 8

        t0 = time.perf_counter()
        mats = find_matrices(g, ranges, arg("max-matrix", 400, lambda s: int(s, 0)))
        out("  matrix scan %.1fs" % (time.perf_counter() - t0))
        if not mats:
            out("RESULT: no-matrix")
            out("VERDICT: PARTIAL - health+origin found, no matrix candidate")
            return 8

        mats.sort(reverse=True)
        hits = []
        for sc, pa, m in mats[:80]:
            for o in origins[:4]:
                p = project(m, o[2], o[3], o[4], W, H)
                if p:
                    hits.append((pa, sc, p, o[1], (o[2], o[3], o[4])))
        out("  projection hits: %d" % len(hits))
        for pa, sc, p, opa, org in hits[:12]:
            out("    matrix %#x score=%d -> origin %#x (%.1f,%.1f,%.1f) = screen (%.0f,%.0f) w=%.1f %s"
                % (pa, sc, opa, org[0], org[1], org[2], p[0], p[1], p[2], p[3]))
        if not hits:
            out("RESULT: no-projection")
            out("VERDICT: PARTIAL - matrix candidates and origins found but none agrees")
            return 8
        best = hits[0]
        out("RESULT: matrix=%#x origin=%#x screen=%.0f,%.0f"
            % (best[0], best[3], best[2][0], best[2][1]))
        out("VERDICT: PASS - physical-only chain validated (health -> origin -> matrix)")
        return 0
    finally:
        try:
            g.close()
        except Exception:                        # noqa: BLE001
            pass


if __name__ == "__main__":
    sys.exit(main())


