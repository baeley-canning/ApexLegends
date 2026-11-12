r"""_mk19.py -- dump once, solve on disk.  The VP is found offline, not by playing.

_mk18 (and qk_vp before it) needed the game to be mid-match, unfocused-broken and
*moving* while a probe polled it.  That is a live-diff experiment, and it fails for
boring reasons: a paused render loop (UAC steals focus), a menu, a match boundary.
None of that is information about where the matrix lives.

A dump is.  Two modes:

  --snap    ONE pass, no waiting, no diffing, no "look around":
              temp\dump\data.bin   the game image's .data, physical, 171 MB
              temp\dump\band.bin   the heap band around the census seeds (<=1 GB)
              temp\dump\meta.txt   image_pa, stamp, sections, ranges, pid, failures
              temp\dump\seeds.txt  the p134 seeds: pa + 0x100 bytes of their record
            The game can be closed afterwards; nothing below needs it again.

  --solve   offline.  No gio, no elevation, no game process:
              every 16f window in the dump that could be a world->clip matrix, each
              projected through each seed reading, ranked by camera-anchor then
              on-screen count.  Re-runnable in seconds, so the oracle can be tuned
              without touching the machine.

The anchor test is the whole point: a dump contains the matrix AND the entity
positions from the same instant, so "the derived camera sits on an entity origin"
is a source-free verdict, and it needs no motion at all.
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
sys.path.insert(0, HERE)

import _vp2d as vp                                          # noqa: E402

DUMP = os.path.join(HERE, "dump")
DATA = os.path.join(DUMP, "data.bin")
BAND = os.path.join(DUMP, "band.bin")
META = os.path.join(DUMP, "meta.txt")
SEEDS = os.path.join(DUMP, "seeds.txt")
OUT = os.path.join(HERE, "_mk19_out.txt")
RECTS = os.path.join(HERE, "_mk19_rects.txt")

MINS = (-16.0, -16.0, 0.0)
MAXS = (16.0, 16.0, 72.0)
CHUNK = 0x100000
BAND_CAP = 0x40000000                                       # 1 GB


def _arg(name, default=None):
    p = "--" + name + "="
    for i, a in enumerate(sys.argv):
        if a == "--" + name and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
        if a.startswith(p):
            return a[len(p):]
    return default


def out(s=""):
    line = "" if s == "" else str(s)
    print(line)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def coverage(ranges, pa, n):
    for lo, hi in ranges:
        if lo <= pa and pa + n <= hi:
            return True
    return False


# ---------------------------------------------------------------- snap (live)

def image_header(g, ranges, base):
    """(size, stamp, [(name, va, vsize)]) or None - the qk_image parse."""
    h = _rd(g, ranges, base, 0x40)
    if not h or h[:2] != b"MZ":
        return None
    lf = u32(h, 0x3C)
    if lf < 0x40 or lf > 0x1000:
        return None
    nt = _rd(g, ranges, base + lf, 0x18 + 0xF0)
    if not nt or nt[:4] != b"PE\0\0":
        return None
    nsec, optsize = u16(nt, 6), u16(nt, 0x14)
    size = u32(nt, 0x18 + 0x38)
    stamp = u32(nt, 0x08)
    sh = _rd(g, ranges, base + lf + 0x18 + optsize, nsec * 40)
    if not sh:
        return None
    secs = []
    for k in range(nsec):
        s = sh[k * 40:(k + 1) * 40]
        if len(s) < 40:
            break
        secs.append((s[:8].rstrip(b"\0").decode("ascii", "replace"),
                     u32(s, 12), u32(s, 8)))
    return size, stamp, secs


def _rd(g, ranges, pa, n, tries=6):
    import dumplive as dl
    if not coverage(ranges, pa, n):
        return None
    try:
        return dl.retry_phys(g, pa, n, tries=tries)
    except OSError:
        return None


def _base():
    p = _arg("offsets", os.path.join(HERE, "qk_offsets.txt"))
    try:
        with open(p, encoding="utf-8") as f:
            for line in f:
                if line.startswith("image_pa="):
                    return int(line.split("=", 1)[1], 16)
    except OSError:
        return None
    return None


def seed_paths():
    p = _arg("seeds", os.path.join(HERE, "_p134_out.txt"))
    pas = []
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            for line in f:
                t = line.strip()
                if t.startswith("SEED "):
                    pas.append(int(t.split()[1], 0))
                elif t.startswith("@0x"):
                    pas.append(int(t.split()[0][1:], 16))
    except OSError:
        return []
    out_list = []
    for a in pas:
        if a not in out_list:
            out_list.append(a)
    return out_list


def dump_region(g, ranges, pa, size, path, label):
    """Stream a physical region to disk, recording refused chunks (R3)."""
    fails, t0 = [], time.time()
    with open(path, "wb") as f:
        off = 0
        while off < size:
            n = min(CHUNK, size - off)
            b = _rd(g, ranges, pa + off, n)
            if b is None or len(b) != n:
                fails.append((off, n))
                b = (b or b"") + b"\0" * (n - len(b or b""))
            f.write(b)
            off += n
            if (off >> 25) != ((off - n) >> 25):
                out("   %s %d MB / %d MB, %d chunk(s) refused, %.0fs"
                    % (label, off // 1048576, size // 1048576, len(fails),
                       time.time() - t0))
    return fails



def _now():
    return time.strftime("%Y-%m-%d %H:%M:%S")


def snap():
    """One pass: copy the image .data, the seed band and the seed records."""
    import gio
    import dumplive as dl
    open(OUT, "w").close()
    os.makedirs(DUMP, exist_ok=True)
    out("=== _mk19 snap %s ===" % _now())
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        out("gio: %s" % e)
        out("VERDICT: FAIL - need elevation for gdrv3")
        return 2
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    pid = dl.find_pid()
    base = _base()
    out("ram_top=%#x ranges=%d (%s)" % (g.ram_top, len(ranges), note))
    out("game pid=%s image_pa=%s" % (pid, "None" if base is None else "%#x" % base))
    if base is None:
        out("VERDICT: FAIL - no image_pa in qk_offsets.txt (run qk_image once)")
        return 1
    hdr = image_header(g, ranges, base)
    if not hdr:
        out("VERDICT: FAIL - no PE at %#x; qk_offsets.txt is from another boot" % base)
        return 1
    size, stamp, secs = hdr
    dv = dsz = None
    for name, va, vs in secs:
        if name == ".data":
            dv, dsz = va, vs
    out("image size=%#x stamp=%#010x sections=%d .data=%s"
        % (size, stamp, len(secs),
           "None" if dv is None else "va=%#x size=%#x (%d MB)"
           % (dv, dsz, dsz // 1048576)))
    if dv is None:
        out("VERDICT: FAIL - that PE has no .data (not the game image)")
        return 1

    pas = seed_paths()
    out("seeds: %d from _p134_out.txt" % len(pas))
    recs = []
    for pa in pas:
        b = _rd(g, ranges, pa, 0x100)
        if b and len(b) == 0x100:
            recs.append((pa, b))
    out("seed records read: %d/%d" % (len(recs), len(pas)))
    with open(SEEDS, "w", encoding="utf-8") as f:
        f.write("# _mk19 %s  image_pa=%#x  %s\n" % (_now(), base, note))
        f.write("# pa 24 floats of the record (fitted as a transform), raw=hex\n")
        for pa, b in recs:
            fl = struct.unpack_from("<24f", b, 0)
            f.write("%#x %s raw=%s\n"
                    % (pa, " ".join("%.6g" % v for v in fl), b[:0x80].hex()))

    fails = dump_region(g, ranges, base + dv, dsz, DATA, ".data")
    out("data.bin %d MB, %d chunk(s) refused"
        % (os.path.getsize(DATA) // 1048576, len(fails)))

    segs, band_fails, off_w = [], [], 0
    if recs:
        wins = cluster_seeds([pa for pa, _ in recs])
        out("seed windows: %d (one per 64 MB bucket holding a seed), %d MB total"
            % (len(wins), sum(n for _, n in wins) // 1048576))
        with open(BAND, "wb") as fb:
            for lo, n in wins:
                buf = b""
                o = 0
                while o < n:
                    c = min(CHUNK, n - o)
                    b = _rd(g, ranges, lo + o, c)
                    if b is None or len(b) != c:
                        band_fails.append((lo + o, c))
                        b = (b or b"") + b"\0" * (c - len(b or b""))
                    buf += b
                    o += c
                fb.write(buf)
                segs.append((lo, n, off_w))
                off_w += n
                out("   %#012x..%#012x  %d MB, %d chunk(s) refused"
                    % (lo, lo + n, n // 1048576, len(band_fails)))
        out("band.bin %d MB, %d chunk(s) refused"
            % (os.path.getsize(BAND) // 1048576, len(band_fails)))

    with open(META, "w", encoding="utf-8") as f:
        f.write("time=%s\n" % _now())
        f.write("pid=%s\n" % pid)
        f.write("image_pa=%#x\n" % base)
        f.write("image_size=%#x\nstamp=%#x\n" % (size, stamp))
        f.write("data_rva=%#x\ndata_size=%#x\n" % (dv, dsz))
        f.write("band_pa=%#x\nband_size=%#x\n" % (segs[0][0] if segs else 0, off_w))
        f.write("segs=%d\n" % len(segs))
        for lo, n, o in segs:
            f.write("seg %#x %#x %#x\n" % (lo, n, o))
        f.write("ranges=%s\n" % note)
        for lo, hi in ranges:
            f.write("range %#x %#x\n" % (lo, hi))
        f.write("data_refused=%d\nband_refused=%d\n" % (len(fails), len(band_fails)))
        for off, n in fails[:64]:
            f.write("refused data +%#x len %#x\n" % (off, n))

    got = os.path.getsize(DATA)
    band_sz = os.path.getsize(BAND) if os.path.exists(BAND) else 0
    alive = dl.find_pid()
    out("game alive at end: %s (pid=%s)" % (alive == pid, alive))
    out("RESULT: data=%d band=%d seeds=%d image_pa=%#x"
        % (got, band_sz, len(recs), base))
    if got == dsz and len(recs) >= 3:
        out("VERDICT: PASS - dump complete (%d MB + %d MB); solve offline"
            % (got // 1048576, band_sz // 1048576))
        return 0
    out("VERDICT: PARTIAL - dump short (data %d/%d bytes, %d seeds)"
        % (got, dsz, len(recs)))
    return 1


# ---------------------------------------------------------------- solve (offline)

def load_meta():
    m = {}
    try:
        with open(META, encoding="utf-8") as f:
            for line in f:
                t = line.split()
                if not t:
                    continue
                if t[0] == "range" and len(t) == 3:
                    m.setdefault("ranges", []).append((int(t[1], 16),
                                                       int(t[2], 16)))
                elif t[0] == "seg" and len(t) == 4:
                    m.setdefault("segs", []).append((int(t[1], 16),
                                                     int(t[2], 16),
                                                     int(t[3], 16)))
                elif "=" in t[0]:
                    k, v = t[0].split("=", 1)
                    if k in ("range", "seg"):
                        continue
                    # "ranges=" / "segs=" summary lines coexist with the
                    # "range"/"seg" record lines, so they must not clobber them
                    if k in ("ranges", "segs"):
                        k += "_note"
                    m[k] = v
    except OSError:
        return None
    return m


def load_seeds():
    """[(pa, [f0..f11])] from the snapshot - no p134 file needed any more."""
    seeds = []
    try:
        with open(SEEDS, encoding="utf-8") as f:
            for line in f:
                t = line.split()
                if len(t) < 13 or t[0].startswith("#"):
                    continue
                seeds.append((int(t[0], 16), [float(x) for x in t[1:13]]))
    except OSError:
        return []
    return seeds


def cluster_seeds(pas, win=0x4000000):
    """One dump window per 64 MB bucket that contains a seed, trimmed to the
    seeds it holds.  The 64 seed records sit in ~10 different 1 GB clusters
    spanning 5..31 GB, so a single contiguous band throws most of them away."""
    wins = {}
    for a in sorted(set(pas)):
        b = a >> 26
        lo, hi = wins.get(b, (a, a + 0x1000))
        wins[b] = (min(lo, a), max(hi, a + 0x1000))
    out_w = []
    for b in sorted(wins):
        lo, hi = wins[b]
        lo = max(b << 26, (lo - 0x100000) & ~0xFFFFF)
        hi = min((b + 1) << 26, (hi + 0x100000 + 0xFFFFF) & ~0xFFFFF)
        if hi > lo:
            out_w.append((lo, hi - lo))
    return out_w


def org_readings(seeds):
    """Entity origins, fitted rather than assumed.

    A seed record is a 3x4 transform: three unit-length, mutually orthogonal
    3-vectors plus a translation.  _mk18/_p134 guessed four flat readings of
    it, and three of those were reading a *rotation column* as a coordinate -
    which is why every anchor test came back meaningless.  So fit: try each
    plausible layout, keep only the ones that actually look like a rotation,
    and take the translation column as the origin.  Flat readings remain as a
    fallback for records that are not transforms at all.
    """
    layouts = (
        ("r16", (0, 1, 2), (4, 5, 6), (8, 9, 10), (3, 7, 11)),
        ("c16", (0, 4, 8), (1, 5, 9), (2, 6, 10), (12, 13, 14)),
        ("r12", (0, 1, 2), (3, 4, 5), (6, 7, 8), (9, 10, 11)),
        ("c12", (0, 3, 6), (1, 4, 7), (2, 5, 8), (9, 10, 11)),
    )
    out_list = []
    for pa, f in seeds:
        if len(f) < 16:
            f = list(f) + [0.0] * (16 - len(f))
        for name, ia, ib, ic, ip in layouts:
            vs = [[f[i] for i in ix] for ix in (ia, ib, ic)]
            ns = [sum(v * v for v in u) ** 0.5 for u in vs]
            if any(n < 0.9 or n > 1.1 for n in ns):
                continue
            dot = max(abs(sum(vs[i][k] * vs[j][k] for k in range(3)))
                      for i in range(3) for j in range(i + 1, 3))
            if dot > 0.05:
                continue
            org = tuple(f[i] for i in ip)
            if any(abs(v) > 20000.0 for v in org):
                continue
            if max(abs(v) for v in org) < 1.0:
                continue
            out_list.append({"pa": pa, "shape": "fit/" + name, "org": org})
    if out_list:
        return out_list
    for pa, f in seeds:                                     # flat fallback
        for name, org in (("contig", (f[0], f[1], f[2])),
                          ("strided", (f[0], f[4], f[8])),
                          ("contig_yz", (f[0], f[2], f[1])),
                          ("strided_yz", (f[0], f[8], f[4]))):
            if any(abs(v) > 20000.0 for v in org) or max(abs(v) for v in org) < 1.0:
                continue
            out_list.append({"pa": pa, "shape": name, "org": org})
    return out_list



def _shape_mask(w):
    """Boolean mask over windows that look like a world->clip matrix in the
    orientation they are written in."""
    import numpy as np
    ok = np.isfinite(w).all(1) & (np.abs(w).max(1) < 1e7)
    if not ok.any():
        return ok
    r0 = np.sqrt((w[:, 0:3] ** 2).sum(1))
    r1 = np.sqrt((w[:, 4:7] ** 2).sum(1))
    r2 = np.sqrt((w[:, 8:11] ** 2).sum(1))
    ok &= (r0 > 1e-3) & (r0 < 8.0) & (r1 > 1e-3) & (r1 < 8.0) \
        & (r2 > 1e-3) & (r2 < 8.0)
    if not ok.any():
        return ok
    tr = np.sqrt(w[:, 3] ** 2 + w[:, 7] ** 2 + w[:, 11] ** 2)
    tc = np.sqrt(w[:, 12] ** 2 + w[:, 13] ** 2 + w[:, 14] ** 2)
    ok &= np.maximum(tr, tc) > 500.0
    if not ok.any():
        return ok
    u0 = w[:, 0:3] / np.maximum(r0, 1e-9)[:, None]
    u1 = w[:, 4:7] / np.maximum(r1, 1e-9)[:, None]
    u2 = w[:, 8:11] / np.maximum(r2, 1e-9)[:, None]
    ok &= (np.abs((u0 * u1).sum(1)) < 0.2) \
        & (np.abs((u0 * u2).sum(1)) < 0.2) \
        & (np.abs((u1 * u2).sum(1)) < 0.2)
    return ok


def windows(buf, cap=4000):
    """Every 16f window in `buf` that could be a world->clip matrix.

    Structural, not temporal: finite, bounded, unit-ish basis rows, an
    orthonormal-ish basis, and a translation term at map scale (thousands of
    units) - a real matrix built at world coordinates has one, noise does not.
    There is NO requirement for a literal 1.0 (a perspective matrix needs none).

    Both storage conventions are tested: a transposed matrix has rows built from
    three *different* basis vectors, so it can only pass after the transpose.
    The transpose test only runs on windows that failed the direct test, i.e.
    almost never, so this stays linear in the dump size.
    No motion, no second read - this is the test a dump exists to allow.
    """
    import numpy as np
    a = np.frombuffer(buf, dtype="<f4")
    n = a.size
    if n < 17:
        return []
    idx_all, step, s = [], 1 << 22, 0
    tr_idx = [0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15]
    with np.errstate(all="ignore"):
        while s + 16 <= n:
            e = min(n, s + step + 15)
            seg = a[s:e]
            # cheap prefilter: a window can only be a matrix if all 16 of its
            # floats are finite and below map scale. One cumsum rejects nearly
            # every window in a dump, so the geometric test (and the transpose
            # retry) only ever sees a handful. Same bound as _shape_mask, so
            # nothing that could pass is dropped here.
            bad = (~np.isfinite(seg)) | (np.abs(seg) >= 1e7)
            if bad.any():
                c = np.concatenate((np.zeros(1, np.int64),
                                    np.cumsum(bad, dtype=np.int64)))
                cand = np.nonzero(c[16:] == c[:-16])[0]
            else:
                cand = np.arange(seg.size - 15)
            if cand.size:
                w = np.lib.stride_tricks.sliding_window_view(seg, 16)[cand]
                ok = _shape_mask(w)
                rest = np.nonzero(~ok)[0]
                if rest.size:
                    ok[rest] = _shape_mask(
                        np.ascontiguousarray(w[rest][:, tr_idx]))
                if ok.any():
                    idx_all.extend((s + cand[ok]).tolist())
            s += step
            if len(idx_all) >= cap:
                break
    return idx_all[:cap]


def scan_file(path, cap=4000, chunk=0x4000000):
    """windows() over a file without holding it in memory: [(off, [m,..])]."""
    res = []
    with open(path, "rb") as f:
        size = os.fstat(f.fileno()).st_size
        pos, carry = 0, b""
        while pos < size and len(res) < cap:
            data = f.read(min(chunk, size - pos))
            if not data:
                break
            body = carry + data
            base = pos - len(carry)          # file offset of body[0]
            for i in windows(body, cap=cap - len(res)):
                res.append((base + i * 4,
                            list(struct.unpack_from("<16f", body, i * 4))))
            carry = body[-64:]               # no window straddles a chunk edge
            pos += len(data)
    return res



def _transpose(m):
    return [m[(i % 4) * 4 + (i // 4)] for i in range(16)]


def score_matrix(m, orgl, W, H):
    """Best reading of the entity set through one matrix, in either storage
    convention, or None."""
    t = _transpose(m)
    shapes = []
    for o in orgl:
        if o["shape"] not in shapes:
            shapes.append(o["shape"])
    best = None
    for tag, mm, camform in (("row", m, m), ("col", m, t)):
        if vp.cam_from_rows(camform) is None:
            continue
        for shape in shapes:
            rows = []
            for o in orgl:
                if o["shape"] != shape:
                    continue
                rr = vp.rect_for(mm, o["org"], MINS, MAXS, W, H, tag=tag)
                rows.append({"org": o["org"], "pa": o["pa"], "rect": rr})
            if len(rows) < 3:
                continue
            st = vp.verify(rows, camform, "row")
            key = (st["on"], st["aspect"],
                   -st["anchor"] if st["anchor"] is not None else -1e9)
            if best is None or key > best[0]:
                best = (key, "%s/%s" % (tag, shape), st, rows)
    return best



def solve():
    import ctypes
    open(OUT, "w").close()
    out("=== _mk19 solve %s (offline) ===" % _now())
    meta = load_meta()
    if meta is None:
        out("VERDICT: FAIL - no %s; run --snap first" % META)
        return 1
    seeds = load_seeds()
    orgl = org_readings(seeds)
    try:
        u = ctypes.windll.user32
        W, H = int(u.GetSystemMetrics(0)), int(u.GetSystemMetrics(1))
    except Exception:                                        # noqa: BLE001
        W, H = 1920, 1080
    out("dump: image_pa=%s stamp=%s rva=%s size=%s band=%s+%s"
        % (meta.get("image_pa"), meta.get("stamp"), meta.get("data_rva"),
           meta.get("data_size"), meta.get("band_pa"), meta.get("band_size")))
    out("screen=%dx%d  seeds=%d  org readings=%d" % (W, H, len(seeds), len(orgl)))
    if len(orgl) < 3:
        out("VERDICT: FAIL - dump has no usable seed readings")
        return 1

    regions = []
    if os.path.exists(DATA):
        regions.append(("data", DATA,
                        int(meta["image_pa"], 16) + int(meta["data_rva"], 16)))
    if os.path.exists(BAND):
        segs = meta.get("segs") or []
        if segs:
            regions.append(("band", BAND, segs))
        elif int(meta.get("band_size", "0"), 16):
            regions.append(("band", BAND, [(int(meta["band_pa"], 16),
                                            int(meta["band_size"], 16), 0)]))

    cands = []
    for label, path, base in regions:
        if label == "data":
            hits = scan_file(path)
            out("  data: %d MB, %d matrix-shaped window(s)"
                % (os.path.getsize(path) // 1048576, len(hits)))
            for o, m in hits:
                cands.append(("data", base + o, m))
        else:
            seen = set()
            for pa, n, o in base:
                key = (pa, n)
                if key in seen:
                    continue
                seen.add(key)
                hits = None
                if o == 0:
                    hits = scan_file(path)   # legacy: the file is this region
                else:
                    with open(path, "rb") as f:
                        f.seek(o)
                        piece = f.read(n)
                    idx = windows(piece)
                    hits = [(i * 4, list(struct.unpack_from("<16f", piece,
                                                            i * 4)))
                            for i in idx]
                out("  band %#x +%d MB, %d matrix-shaped window(s)"
                    % (pa, n // 1048576, len(hits)))
                for off, m in hits:
                    cands.append(("band+%#x" % (pa,), pa + off, m))

    out("  candidates: %d - scoring against %d seed reading(s)"
        % (len(cands), len(orgl)))
    scored = []
    for label, pa, m in cands:
        b = score_matrix(m, orgl, W, H)
        if b is None:
            continue
        key, shape, st, rows = b
        if st["anchor"] is not None and st["anchor"] > 400.0:
            continue
        scored.append((key, label, pa, shape, st, rows))
    scored.sort(key=lambda t: t[0], reverse=True)
    out("  survivors (camera within 400 units of a seed): %d" % len(scored))
    for key, label, pa, shape, st, rows in scored[:15]:
        out("   %-4s pa=%#012x on=%d/%d aspect=%d anchor=%s shape=%s"
            % (label, pa, st["on"], st["n"], st["aspect"],
               "None" if st["anchor"] is None else "%.1f" % st["anchor"], shape))

    if not scored:
        out("RESULT: 0 survivors")
        out("VERDICT: FAIL - no matrix in the dump puts the camera on an entity")
        return 1
    key, label, pa, shape, st, rows = scored[0]
    rva = pa - int(meta["image_pa"], 16) if label == "data" else None
    with open(RECTS, "w", encoding="utf-8") as f:
        f.write("# _mk19 %s  %s pa=%#x shape=%s screen=%dx%d\n"
                % (_now(), label, pa, shape, W, H))
        for r in rows:
            rr = r["rect"]
            if not rr:
                f.write("%#011x off-screen\n" % r["pa"])
                continue
            f.write("%#011x x0=%7.1f y0=%7.1f x1=%7.1f y1=%7.1f w=%6.1f "
                    "h=%6.1f d=%7.0f corners=%d\n"
                    % (r["pa"], rr["x0"], rr["y0"], rr["x1"], rr["y1"],
                       rr["x1"] - rr["x0"], rr["y1"] - rr["y0"], rr["depth"],
                       rr["corners"]))
    out("rects written: %s" % RECTS)
    out("RESULT: %s pa=%#x%s shape=%s on=%d/%d aspect=%d anchor=%s"
        % (label, pa, "" if rva is None else " rva=%#x" % rva, shape,
           st["on"], st["n"], st["aspect"],
           "None" if st["anchor"] is None else "%.1f" % st["anchor"]))
    ok = (st["on"] >= 3 and st["aspect"] >= 3 and st["anchor"] is not None
          and st["anchor"] <= 128.0)
    if ok:
        out("VERDICT: PASS - %d rect(s) on screen, camera %.1f units from a seed, "
            "all from one dump" % (st["on"], st["anchor"]))
    else:
        out("VERDICT: PARTIAL - on=%d aspect=%d anchor=%s (need on>=3, "
            "aspect>=3, anchor<=128)"
            % (st["on"], st["aspect"],
               "None" if st["anchor"] is None else "%.1f" % st["anchor"]))
    return 0 if ok else 1


def main():
    if "--snap" in sys.argv:
        return snap()
    if "--solve" in sys.argv:
        return solve()
    print("usage: _mk19.py --snap | --solve   [--seeds=PATH] [--offsets=PATH]")
    return 2


if __name__ == "__main__":
    sys.exit(main())
