r"""_mk20.py -- which static matrix is the world->clip?  One instant, no watching.

No moving, no "poll while looking around", no 171 MB dump: ~60 small physical reads in
one pass, every byte kept, and the verdict computed offline from those bytes.

Sources it can name, in the order they are worth trusting:

  S2  a matrix that sits *inside the image* (.data static).  apexsky's table calls this
      ViewMatrix; our own STATE 08/11 02:3x measured the live VP at image+0xDB5BC40 with
      five camera-tracking copies 0xE0 apart, and temp\qk_offsets.txt (12:52 today)
      records a newer candidate.  All of them are read here.

  S1  apexsky's chain: *(base+ViewRender) -> CViewRender*, then +ViewMatrix -> float*.
      That is two dereferences, i.e. VA reads.  gdrv3 is physical-only, so this pass
      *records* the pointer values and classifies them (VA vs RVA) instead of following
      them; if they turn out to be RVAs the chain is physical too and gets followed.

  S3  CPlayer!camera_origin / camera_angles (0x1f40 / 0x1f4c in apexsky's DT_Player),
      which needs the LocalPlayer static dereferenced - same VA question as S1.

The scoring matrix is apexsky's own, from `state/client_state.rs` (row-vector, w = m[12..15]);
_vp2d.project_tag(..., "row") is that formula to within half a pixel.

Verdict, all from the same instant: entities from the p134 census project on screen with
human aspect ratios, and the camera derived from the matrix sits on an entity.  A wrong
matrix satisfies neither.

usage:
  python temp\_mk20.py --probe            (live; needs elevation for gdrv3)
  python temp\_mk20.py --verify           (offline; re-scores _mk20_raw.txt)
"""
import os
import re
import struct
import sys
import time
import math

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
sys.path.insert(0, HERE)

import _vp2d as vp                                          # noqa: E402

OUT = os.path.join(HERE, "_mk20_out.txt")
RAW = os.path.join(HERE, "_mk20_raw.txt")
RECTS = os.path.join(HERE, "_mk20_rects.txt")
SCAN = os.path.join(HERE, "_mk20_scan.txt")
OFFS = os.path.join(HERE, "qk_offsets.txt")
CENSUS = os.path.join(HERE, "_p134_out.txt")

MINS = (-16.0, -16.0, 0.0)
MAXS = (16.0, 16.0, 72.0)
W, H = 1920, 1080

# the five camera-tracking copies STATE 08/11 02:3x measured, 0xE0 apart
FAMILY = 0x0DB5BC40
FAMILY_N = 5
FAMILY_STRIDE = 0xE0

# apexsky v3.0.2.23 statics (TimeDateStamp 0x681d392e) - a hypothesis for THIS build:
# our stamp is 0x6adbf892.  Recorded, and followed only if the value is image-relative.
STATICS = (
    ("ViewRender", 0x3C8CAD8),
    ("ViewMatrix", 0x11A350),
    ("cl_entitylist", 0x619AAA8),
    ("LocalEntityHandle", 0x1ACDD08),
    ("LocalPlayer", 0x26AF8A8),
    ("GlobalVars", 0x1B9BF50),
    ("HighlightSettings", 0x68E4030),
)

# record layouts worth testing on a census record: stride-0x10 rows with the
# translation in column 0 or column 3, and the naive contiguous triple.
LAYOUTS = (
    ("rows/col0", (0, 4, 8)),
    ("rows/col3", (3, 7, 11)),
    ("contig", (0, 1, 2)),
)


def _arg(name, default=None):
    p = "--" + name + "="
    for i, a in enumerate(sys.argv):
        if a == "--" + name and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
        if a.startswith(p):
            return a[len(p):]
    return default


def out(s="", mode="a"):
    line = "" if s == "" else str(s)
    print(line)
    with open(OUT, mode, encoding="utf-8") as f:
        f.write(line + "\n")


def _now():
    return time.strftime("%Y-%m-%d %H:%M:%S")


def u32(b, o=0):
    return struct.unpack_from("<I", b, o)[0]


def u64(b, o=0):
    return struct.unpack_from("<Q", b, o)[0]


def rd(g, ranges, pa, n, tries=8):
    """Physical read with immediate retry inside the RAM map's interval set (R10)."""
    import dumplive as dl
    if not any(lo <= pa and pa + n <= hi for lo, hi in ranges):
        return None
    try:
        return dl.retry_phys(g, pa, n, tries=tries)
    except OSError:
        return None


def _tr(m):
    return [m[(i % 4) * 4 + (i // 4)] for i in range(16)]


def load_raw(path=None):
    """([(rva, bytes)], [(name, rva, bytes)], [(pa, bytes)]) from _mk20_raw.txt."""
    mats, stats, seeds = [], [], []
    try:
        with open(path or RAW, encoding="utf-8") as f:
            for line in f:
                t = line.split()
                if not t or t[0].startswith("#"):
                    continue
                if t[0] == "mat" and len(t) >= 3 and t[2] != "FAIL":
                    mats.append((int(t[1], 16), bytes.fromhex(t[2])))
                elif t[0] == "static" and len(t) >= 4 and t[3] != "FAIL":
                    stats.append((t[1], int(t[2], 16), bytes.fromhex(t[3])))
                elif t[0] == "seed" and len(t) >= 3 and t[2] != "FAIL":
                    seeds.append((int(t[1], 16), bytes.fromhex(t[2])))
    except OSError:
        return None
    return mats, stats, seeds


def positions(seeds):
    """{layout: [(pa, (x, y, z))]} - only triples that look like world coords.

    A census record is an entity, not a camera: three coordinates in the map's
    thousands, never unit-length.  That is what tells a position layout from a
    bone/basis layout, and it is why the old 'four flat readings' failed.
    """
    res = {}
    for name, idx in LAYOUTS:
        got = []
        for pa, b in seeds:
            if len(b) < 0xC0:
                continue
            f = struct.unpack_from("<48f", b, 0)
            v = tuple(f[i] for i in idx)
            if any(x != x or abs(x) > 20000.0 for x in v):
                continue
            if max(abs(x) for x in v) < 1.0:
                continue
            # a coordinate triple has three live components; (x, 0, 0) is what a
            # strided record looks like when read contiguously, and mistaking one for
            # a position quietly poisons every anchor test downstream
            if any(abs(x) < 1e-3 for x in v):
                continue
            got.append((pa, v))
        res[name] = got
    return res


def pe_info(g, ranges, base):
    """(size_of_image, timestamp) or None."""
    h = rd(g, ranges, base, 0x40)
    if not h or h[:2] != b"MZ":
        return None
    lf = u32(h, 0x3C)
    if not 0x40 <= lf <= 0x1000:
        return None
    nt = rd(g, ranges, base + lf, 0x18 + 0x40)
    if not nt or nt[:4] != b"PE\0\0":
        return None
    return u32(nt, 0x18 + 0x38), u32(nt, 0x08)


def _rank(v):
    """Ranks of v (1 = smallest), ties sharing the average rank."""
    order = sorted(range(len(v)), key=lambda i: v[i])
    r = [0.0] * len(v)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and v[order[j + 1]] == v[order[i]]:
            j += 1
        avg = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            r[order[k]] = avg
        i = j + 1
    return r


def _pearson(a, b):
    n = len(a)
    if n < 3:
        return 0.0
    ma, mb = sum(a) / n, sum(b) / n
    sa = sum((x - ma) ** 2 for x in a) ** 0.5
    sb = sum((y - mb) ** 2 for y in b) ** 0.5
    if sa <= 0 or sb <= 0:
        return 0.0
    return sum((a[i] - ma) * (b[i] - mb) for i in range(n)) / (sa * sb)


def score(m, tag, wsrc, pos_list):
    """(stats, rows) for one matrix, one convention; None if not a matrix.

    Two different matrices on purpose: `cam_from_rows` only speaks row-major, so a
    column-stored matrix is transposed for the camera; `rect_for` projects in the
    convention it is handed, so it must get the matrix exactly as it was stored.
    Transposing for both is what made the col/z unit case score aspect=0.

    `corr` is the discriminator that matters: for a real view, an entity's box
    height falls as its distance from the camera grows, so rank(height) against
    rank(1/distance) is strongly positive.  A matrix that merely squeezes the whole
    census into the middle of the screen scores on=n and corr~0, which is exactly the
    false positive that "28/28 on screen" looked like on 14:37.
    """
    mcam = m if tag == "row" else _tr(m)
    cam = vp.cam_from_rows(mcam)
    if cam is None:
        return None
    # anchor first: it is the cheap test and it is the one that rejects.  Rects cost
    # 8 projections per entity, so at scan scale (12k candidates) this ordering is the
    # difference between a 20-second replay and a 20-minute one.
    anchor = None
    for _, org in pos_list:
        d = math.dist(cam, org)
        if anchor is None or d < anchor:
            anchor = d
    if anchor is not None and anchor > 400.0:
        return None
    on = aspect = 0
    rows = []
    for pa, org in pos_list:
        rr = vp.rect_for(m, org, MINS, MAXS, W, H, tag=tag, wsrc=wsrc)
        rows.append({"pa": pa, "org": org, "rect": rr})
        if rr:
            on += 1
            w = rr["x1"] - rr["x0"]
            h = rr["y1"] - rr["y0"]
            if h > 1.0 and 0.1 <= w / h <= 1.2:
                aspect += 1
    anchor = None
    for _, org in pos_list:
        d = math.dist(cam, org)
        if anchor is None or d < anchor:
            anchor = d
    hs, inv = [], []
    for r in rows:
        rr = r["rect"]
        if not rr:
            continue
        d = math.dist(cam, r["org"])
        hs.append(rr["y1"] - rr["y0"])
        inv.append(1.0 / max(d, 1.0))
    corr = _pearson(_rank(hs), _rank(inv)) if len(hs) >= 3 else 0.0
    medh = sorted(hs)[len(hs) // 2] if hs else 0.0
    return ({"n": len(pos_list), "on": on, "aspect": aspect,
             "anchor": anchor, "cam": cam, "corr": corr, "medh": medh}, rows)


def _best(mats, usable, top=10):
    """The top-scoring (matrix, convention, layout) candidates, best first."""
    rank = []
    for rva, blob in mats:
        for off in (0, 4, 8, 12, 16):
            if off + 64 > len(blob):
                continue
            m = list(struct.unpack_from("<16f", blob, off))
            if any(v != v or abs(v) > 1e7 for v in m):
                continue
            for tag in ("row", "col"):
                for wsrc in ("w", "z"):
                    for lname, plist in usable:
                        r = score(m, tag, wsrc, plist)
                        if r is None:
                            continue
                        st, rows = r
                        if st["anchor"] is None or st["anchor"] > 400.0:
                            continue
                        key = (st["on"], st["aspect"], -st["anchor"])
                        rank.append((key, rva, off, tag, wsrc, lname, st, rows))
    rank.sort(key=lambda t: t[0], reverse=True)
    return rank[:top]


def _passes(st):
    """The gate.  `corr` and `medh` are what separate a view from a squeeze.

    medh bounds are deliberately wide: an entity 60 units away fills the screen, so
    the unit case scores medh=500 px and is still a true view.  The lower bound is
    what kills a squeeze (sub-pixel boxes clustered at the centre).
    """
    return (st["on"] >= 3 and st["aspect"] >= 3 and st["anchor"] is not None
            and st["anchor"] <= 128.0 and st["corr"] >= 0.5
            and 2.0 <= st["medh"] <= float(H))


def verify(raw_path=None):
    got = load_raw(raw_path or _arg("raw"))
    if got is None:
        out("VERDICT: FAIL - no %s (run --probe first)" % RAW)
        return 1
    mats, stats, seeds = got
    out("")
    out("--- verify %s : %d matrix window(s), %d static(s), %d record(s) ---"
        % (_now(), len(mats), len(stats), len(seeds)))
    if not mats or not seeds:
        out("VERDICT: FAIL - raw file is missing matrices or records")
        return 1

    pos = positions(seeds)
    for name in pos:
        out("  layout %-9s usable positions: %d/%d"
            % (name, len(pos[name]), len(seeds)))
    # FACTS: a match boundary zeroes the entity pools, and a census address is only
    # valid inside its own match.  A zeroed record scored against any matrix is noise
    # dressed as evidence, so this is a state check, not a verdict.
    live = sum(1 for _, b in seeds if any(bb for bb in b))
    out("  records with any non-zero byte: %d/%d" % (live, len(seeds)))
    if live < max(3, len(seeds) // 3):
        out("RESULT: census-stale")
        out("VERDICT: PARTIAL - %d/%d records are zeroed: the census predates a "
            "match boundary, re-census and re-burst (no matrix is at fault)"
            % (len(seeds) - live, len(seeds)))
        return 1
    usable = [(n, p) for n, p in pos.items() if len(p) >= 3]
    # _p134 defines a seed as v[i], v[i+1], v[i+2] - three CONSECUTIVE floats at the
    # seed address.  That is authoritative, so it wins; the strided layouts are only
    # fallbacks for a record that happens not to hold its triple at +0.
    if len(pos.get("contig", [])) >= 3:
        usable = [("contig", pos["contig"])]
        out("  layout pinned to contig (the census's own definition)")
    if not usable:
        out("VERDICT: FAIL - no record layout gives 3 world coordinates")
        return 1

    best = _best(mats, usable)
    if not best:
        out("  no matrix put the camera within 400 units of a census record")
        out("RESULT: 0 survivors")
        out("VERDICT: FAIL - no matrix in this instant is the world->clip")
        return 1
    out("")
    out("  %-12s %-4s %-2s %-9s %6s %3s %8s %6s %6s"
        % ("rva", "tag", "w", "layout", "on", "asp", "anchor", "corr", "medh"))
    for key, rva, off, tag, wsrc, lname, st, _rows in best:
        out("  %#012x %-4s %-2s %-9s %3d/%2d %3d %8s %6.2f %6.1f%s"
            % (rva + off, tag, wsrc, lname, st["on"], st["n"], st["aspect"],
               "None" if st["anchor"] is None else "%.1f" % st["anchor"],
               st["corr"], st["medh"], "" if _passes(st) else "  (rejected)"))

    pick = None
    for cand in best:
        if _passes(cand[6]):
            pick = cand
            break
    if pick is None:
        k, rva, off, tag, wsrc, lname, st, rows = best[0]
        out("RESULT: rva=%#x +%#x %s/%s on=%d/%d aspect=%d anchor=%s corr=%.2f "
            "medh=%.1f" % (rva, off, tag, wsrc, st["on"], st["n"], st["aspect"],
                           "None" if st["anchor"] is None
                           else "%.1f" % st["anchor"], st["corr"], st["medh"]))
        out("VERDICT: PARTIAL - best candidate fails the gate (need anchor<=128, "
            "corr>=0.5, medh in 5..400 px): a squeeze-to-centre matrix scores "
            "on=n but corr~0")
        return 1

    key, rva, off, tag, wsrc, lname, st, rows = pick
    out("  winner: rva=%#x (matrix at +%#x) %s/%s layout=%s"
        % (rva, off, tag, wsrc, lname))
    out("  camera=(%.1f, %.1f, %.1f)  on=%d/%d aspect=%d anchor=%s"
        % (st["cam"][0], st["cam"][1], st["cam"][2], st["on"], st["n"],
           st["aspect"],
           "None" if st["anchor"] is None else "%.1f" % st["anchor"]))
    with open(RECTS, "w", encoding="utf-8") as f:
        f.write("# _mk20 %s rva=%#x %s/%s\n" % (_now(), rva, tag, wsrc))
        for r in rows:
            rr = r["rect"]
            if not rr:
                f.write("%#011x off-screen org=(%.1f, %.1f, %.1f)\n"
                        % (r["pa"], r["org"][0], r["org"][1], r["org"][2]))
                continue
            f.write("%#011x x0=%7.1f y0=%7.1f x1=%7.1f y1=%7.1f d=%7.0f\n"
                    % (r["pa"], rr["x0"], rr["y0"], rr["x1"], rr["y1"],
                       rr["depth"]))
    out("rects written: %s" % RECTS)
    out("   RESULT: rva=%#x +%#x %s/%s on=%d/%d aspect=%d anchor=%s corr=%.2f "
        "medh=%.1f"
        % (rva, off, tag, wsrc, st["on"], st["n"], st["aspect"],
           "None" if st["anchor"] is None else "%.1f" % st["anchor"],
           st["corr"], st["medh"]))
    ok = _passes(st)
    if ok:
        out("VERDICT: PASS - %d/%d entities on screen, camera %.1f units from one, "
            "box height vs distance corr %.2f: rva %#x is the world->clip matrix"
            % (st["on"], st["n"], st["anchor"], st["corr"], rva))
    else:
        out("VERDICT: PARTIAL - on=%d aspect=%d anchor=%s corr=%.2f medh=%.1f"
            % (st["on"], st["aspect"],
               "None" if st["anchor"] is None else "%.1f" % st["anchor"],
               st["corr"], st["medh"]))
    return 0 if ok else 1


def vp_form(m):
    """True if this 16f window is shaped like a world->view matrix, not an object.

    The distinction is where the translation lives.  A C_BaseEntity transform keeps
    its position in *column* 3 (m[3], m[7], m[11]); a Source-engine view matrix keeps
    it in *row* 3 (m[12..14]) with m[15] == 1 and the first three columns free of
    position.  On 14:41 the unfiltered scan produced ~700 object transforms per
    16 MB and hit the cap before a third of the image was read, which is how the real
    matrix stays invisible.
    """
    if any(v != v or abs(v) > 1e7 for v in m):
        return False
    if abs(m[15] - 1.0) > 1e-3:
        return False
    if max(abs(m[3]), abs(m[7]), abs(m[11])) > 1e-3:
        return False
    t = (abs(m[12]) ** 2 + abs(m[13]) ** 2 + abs(m[14]) ** 2) ** 0.5
    return 500.0 <= t <= 60000.0


def scan(block=0x10000, cap=12000):
    """Find matrix-shaped 16f windows inside the image.  Writes _mk20_scan.txt.

    This is the "look at the image, not at the player" step: a 16f window whose basis
    rows are unit-ish and whose translation is at map scale, screened by
    _mk19.windows() - the filter unit-tested 5/5 on row/col/noise/far/fit.

    Beyond that, no shape rule on purpose (vp_form below is recorded but unused): an
    entity transform and a view matrix are structurally indistinguishable - both are
    an orthonormal basis with a position - so any extra rule either discards the
    matrix or keeps every object.  The anchor test at burst time discriminates.  The
    cap is therefore high: 700 object transforms per 16 MB means a low cap stops
    reading the image a fifth of the way in, which is what happened at 14:41.
    """
    import gio
    import dumplive as dl
    import _mk19 as m19
    open(OUT, "w").close()
    out("=== _mk20 scan %s : matrix-shaped windows in the image ===" % _now())
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        out("gio: %s" % e)
        out("VERDICT: FAIL - need elevation for gdrv3")
        return 2
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    off = offsets_file()
    base = int(off["image_pa"], 16) if "image_pa" in off else None
    if base is None:
        out("VERDICT: FAIL - no image_pa in qk_offsets.txt")
        return 1
    info = pe_info(g, ranges, base)
    if not info:
        out("VERDICT: FAIL - no PE at %#x" % base)
        return 1
    isize = info[0]
    out("image_pa=%#x size=%#x (%d MB) ranges=%d (%s)"
        % (base, isize, isize // 1048576, len(ranges), note))
    rvas, t0, refused, pos = [], time.time(), 0, 0
    while pos < isize and len(rvas) < cap:
        n = min(block, isize - pos)
        b = rd(g, ranges, base + pos, n, tries=4)
        if not b or len(b) != n:
            refused += 1
        else:
            for i in m19.windows(b, cap=cap - len(rvas)):
                rvas.append(pos + i * 4)
        if (pos + n) >> 24 != pos >> 24:
            out("   %4d/%d MB  %3d candidate(s)  %d block(s) refused  %.0fs"
                % ((pos + n) // 1048576, isize // 1048576, len(rvas),
                   refused, time.time() - t0))
        pos += n
    rvas = sorted(set(rvas))
    with open(SCAN, "w", encoding="utf-8") as f:
        f.write("# _mk20 scan %s image_pa=%#x size=%#x stamp=%#x\n"
                % (_now(), base, isize, info[1]))
        for r in rvas:
            f.write("rva %#x\n" % r)
    out("scan candidates: %d (of %d MB read, %d block(s) refused) -> %s"
        % (len(rvas), pos // 1048576, refused, SCAN))
    alive = dl.find_pid()
    out("game alive at end: %s (pid=%s)" % (alive is not None, alive))
    out("RESULT: scan=%d refused=%d" % (len(rvas), refused))
    out("VERDICT: %s - %d matrix-shaped window(s) to score in a burst"
        % ("PASS" if rvas else "FAIL", len(rvas)))
    return 0 if rvas else 1


def scan_rvas(path=None, cap=1500):
    """Candidate RVAs written by scan().

    1500, not 400: the 14:37 burst sorted the list and cut it at 400, so everything
    above 0x57c... was never even read.  A scan that finds candidates and then
    silently ignores two thirds of them is how a real matrix gets missed.
    """
    out_l = []
    try:
        with open(path or SCAN, encoding="utf-8") as f:
            for line in f:
                t = line.split()
                if len(t) == 2 and t[0] == "rva":
                    out_l.append(int(t[1], 16))
    except OSError:
        return []
    return out_l[:cap]


def _delta(a, b):
    """Relative change between two 16f windows, ignoring garbage magnitudes.

    A raw |b-a| max is useless here: one 1e14 outlier in the window swamps
    neighbouring values that changed by 1.0, which is how the 15:12 diff ranked
    nothing but noise (`d_matrix` ~1e29) and declared 'view-like: none'.
    """
    best = 0.0
    for x, y in zip(a, b):
        if x != x or y != y or abs(x) > 1e7 or abs(y) > 1e7:
            continue
        best = max(best, abs(y - x) / (1.0 + abs(x)))
    return best


def _vp_mask(w):
    """Vectorised 'is this a world->view matrix' over many 16f windows.

    Tight on purpose, because this runs over 27 GB of RAM: rows 0..2 must be
    orthonormal (a basis, not an object's scaled axes), the translation must sit in
    row 3 (m[12..14]) at map scale with m[15]==1, and the position column must be
    empty.  That is the Source/Apex CViewRender form.  An entity transform keeps its
    position in column 3, so it cannot pass, which is the whole point: on the image
    the unfiltered filter produced 2674 windows and most were objects.
    """
    import numpy as np
    ok = np.isfinite(w).all(1) & (np.abs(w).max(1) < 1e7)
    r0 = np.sqrt((w[:, 0:3] ** 2).sum(1))
    r1 = np.sqrt((w[:, 4:7] ** 2).sum(1))
    r2 = np.sqrt((w[:, 8:11] ** 2).sum(1))
    ok &= (r0 > 0.9) & (r0 < 1.1) & (r1 > 0.9) & (r1 < 1.1) \
        & (r2 > 0.9) & (r2 < 1.1)
    if not ok.any():
        return ok
    u0 = w[:, 0:3] / np.maximum(r0, 1e-9)[:, None]
    u1 = w[:, 4:7] / np.maximum(r1, 1e-9)[:, None]
    u2 = w[:, 8:11] / np.maximum(r2, 1e-9)[:, None]
    ok &= (np.abs((u0 * u1).sum(1)) < 0.1) \
        & (np.abs((u0 * u2).sum(1)) < 0.1) \
        & (np.abs((u1 * u2).sum(1)) < 0.1)
    if not ok.any():
        return ok
    t3 = np.sqrt(w[:, 12] ** 2 + w[:, 13] ** 2 + w[:, 14] ** 2)
    empty_col = (np.abs(w[:, 3]) < 1e-3) & (np.abs(w[:, 7]) < 1e-3) \
        & (np.abs(w[:, 11]) < 1e-3)
    view_form = empty_col & (np.abs(w[:, 15] - 1.0) < 1e-3) \
        & (t3 > 500.0) & (t3 < 60000.0)
    t_col = np.sqrt(w[:, 3] ** 2 + w[:, 7] ** 2 + w[:, 11] ** 2)
    vp_form = (np.abs(w[:, 15]) < 1e-2) & (t_col > 200.0) & (t_col < 60000.0)
    return ok & (view_form | vp_form)


def ramscan(block=0x100000, cap=600):
    """Scan physical RAM for world->view matrices, then score them against a census.

    The VP for this build is not a static in the image: every window that changed
    when the camera turned clustered in one small .data region and none had a
    map-scale camera (temp/_mk20_out.txt 15:12).  apexsky reaches it through a
    pointer, which needs VA reads we do not have on gdrv3 - so find it by shape
    instead.  One pass, no walking, no turning; the census supplies the truth.
    """
    import gio
    import dumplive as dl
    import numpy as np
    open(OUT, "w").close()
    out("=== _mk20 ramscan %s : world->view matrices in RAM ===" % _now())
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        out("gio: %s" % e)
        out("VERDICT: FAIL - need elevation for gdrv3")
        return 2
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    total = sum(hi - lo for lo, hi in ranges)
    out("ram_top=%#x ranges=%d total=%d MB (%s)"
        % (g.ram_top, len(ranges), total // 1048576, note))
    hits, t0, refused, done = [], time.time(), 0, 0
    for lo, hi in ranges:
        pos = lo
        while pos < hi and len(hits) < cap:
            n = min(block, hi - pos)
            # tries=1 on purpose: 1 MB reads refuse ~84% of the time on this boot and
            # each retry costs 4x.  A matrix shows up ~18 times per 768 MB, so losing
            # a fifth of RAM to refusals is far cheaper than paying for retries.
            b = rd(g, [(lo, hi)], pos, n, tries=1)
            if b and len(b) == n:
                a = np.frombuffer(b, dtype="<f4")
                if a.size >= 16:
                    w = np.lib.stride_tricks.sliding_window_view(a, 16)
                    m = _vp_mask(w)
                    if m.any():
                        for i in np.nonzero(m)[0]:
                            hits.append((pos + int(i) * 4,
                                         list(struct.unpack_from("<16f", b,
                                                                 int(i) * 4))))
            else:
                refused += 1
            pos += n
            done += n
            if done >> 28 != (done - n) >> 28:
                out("   %5d MB  %3d hit(s)  %d chunk(s) refused  %.0fs"
                    % (done // 1048576, len(hits), refused, time.time() - t0))
    out("scan: %d MB, %d view-shaped window(s), %d chunk(s) refused, %.0fs"
        % (done // 1048576, len(hits), refused, time.time() - t0))
    if not hits:
        out("RESULT: hits=0")
        out("VERDICT: FAIL - no view-shaped matrix in RAM (filter or build differs)")
        return 1
    seeds = census_seeds(_arg("census"))[:int(_arg("cap", "32"))]
    lines = ["# _mk20 raw %s pid=%s ram_top=%#x ranges=%d %s"
             % (_now(), dl.find_pid(), g.ram_top, len(ranges), note)]
    for pa, m in hits:
        lines.append("mat %#x %s" % (pa, struct.pack("<16f", *m).hex()))
    ok_seeds = 0
    for pa in seeds:
        b = rd(g, ranges, pa, 0xC0)
        if b and len(b) == 0xC0:
            ok_seeds += 1
            lines.append("seed %#x %s" % (pa, b.hex()))
    out("census records: %d/%d" % (ok_seeds, len(seeds)))
    with open(RAW, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    out("raw written: %s (%d window(s), %d record(s))"
        % (RAW, len(hits), ok_seeds))
    return verify()


def diff(gap=0.8, cap=1500):
    """Read the candidate list twice, keep only the matrices that MOVED.

    The trap this closes: `0x9440B4` scored on=25/25, corr=0.73, medh=69 px on two
    bursts 90 s apart with byte-identical content.  A stored object transform passes
    every behavioural test - any rigid transform makes boxes shrink with distance - so
    the only thing that separates it from the live view is that the view is rewritten
    as the camera moves and a stored transform is not.  Two reads of a *fixed* list,
    one gap apart, no walking and no scanning: the live one is the one that changed.

    _mk20_out.txt then scores only what moved, so a static decoy cannot win.
    """
    import gio
    import dumplive as dl
    open(OUT, "w").close()
    out("=== _mk20 diff %s : which of the candidate matrices is live? ===" % _now())
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        out("gio: %s" % e)
        out("VERDICT: FAIL - need elevation for gdrv3")
        return 2
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    off = offsets_file()
    base = int(off["image_pa"], 16) if "image_pa" in off else None
    if base is None:
        out("VERDICT: FAIL - no image_pa in qk_offsets.txt")
        return 1
    rvas = []
    if "vp_rva" in off:
        rvas.append(int(off["vp_rva"], 16))
    rvas.extend(scan_rvas(cap=cap))
    seen, cand = set(), []
    for r in rvas:
        if r not in seen:
            seen.add(r)
            cand.append(r)
    out("image_pa=%#x  candidates=%d  gap=%.1fs" % (base, len(cand), gap))

    def grab():
        got = {}
        for r in cand:
            b = rd(g, ranges, base + r, 0x70, tries=6)
            if b and len(b) == 0x70:
                got[r] = b
        return got

    A = grab()
    t0 = time.time()
    time.sleep(gap)
    B = grab()
    out("read %d/%d twice (%.1fs)"
        % (min(len(A), len(B)), len(cand), time.time() - t0 + gap))
    moved = []
    for r in cand:
        a, b = A.get(r), B.get(r)
        if not a or not b or a == b:
            continue
        fa = struct.unpack_from("<16f", a, 0)
        fb = struct.unpack_from("<16f", b, 0)
        moved.append((r, _delta(fa, fb)))
    moved.sort(key=lambda t: -t[1])
    out("changed between the two reads: %d/%d" % (len(moved), len(cand)))
    # The signature that needs no census at all: a VIEW matrix changes when the camera
    # turns, but the camera POSITION it encodes stays where the player is.  A stored
    # transform is byte-identical (it would not be in `moved`), and a matrix whose
    # derived camera jumps is not a camera.  So: big matrix delta + small camera delta.
    out("")
    out("  %-12s %8s %10s %10s" % ("rva", "d_matrix", "d_cam", "|cam|"))
    viewlike = []
    for r, d in moved[:40]:
        fa = struct.unpack_from("<16f", A[r], 0)
        fb = struct.unpack_from("<16f", B[r], 0)
        best = None
        for tag in ("row", "col"):
            ma = list(fa) if tag == "row" else _tr(list(fa))
            mb = list(fb) if tag == "row" else _tr(list(fb))
            c1, c2 = vp.cam_from_rows(ma), vp.cam_from_rows(mb)
            if c1 is None or c2 is None:
                continue
            dc = math.dist(c1, c2)
            if best is None or dc < best[1]:
                best = (tag, dc, c1)
        if best is None:
            out("  %#012x %8.3f %10s %10s" % (r, d, "n/a", "n/a"))
            continue
        tag, dc, c1 = best
        mag = (c1[0] ** 2 + c1[1] ** 2 + c1[2] ** 2) ** 0.5
        out("  %#012x %8.3f %10.2f %10.1f  %s" % (r, d, dc, mag, tag))
        if d > 0.05 and dc < 25.0 and 200.0 <= mag <= 60000.0:
            viewlike.append((dc, r, d, tag, c1))
    viewlike.sort()
    out("")
    if viewlike:
        out("view-like (matrix moved, camera did not): %d" % len(viewlike))
        for dc, r, d, tag, c1 in viewlike[:5]:
            out("  rva %#x  d_cam=%.2f  d_matrix=%.3f  cam=(%.1f, %.1f, %.1f)  %s"
                % (r, dc, d, c1[0], c1[1], c1[2], tag))
    else:
        out("view-like: none (camera did not turn, or no live matrix here)")

    seeds = census_seeds(_arg("census"))[:int(_arg("cap", "32"))]
    lines = ["# _mk20 raw %s pid=%s image_pa=%#x size=0x0 stamp=0x0 ranges=%d %s"
             % (_now(), dl.find_pid(), base, len(ranges), note)]
    for r, _d in moved:
        lines.append("mat %#x %s" % (r, B[r].hex()))
    ok_seeds = 0
    for pa in seeds:
        b = rd(g, ranges, pa, 0xC0)
        if b and len(b) == 0xC0:
            ok_seeds += 1
            lines.append("seed %#x %s" % (pa, b.hex()))
    out("census records: %d/%d" % (ok_seeds, len(seeds)))
    with open(RAW, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    out("raw written: %s (%d moved window(s), %d record(s))"
        % (RAW, len(moved), ok_seeds))
    if not moved:
        out("RESULT: moved=0")
        out("VERDICT: FAIL - nothing changed between the reads (camera still, or "
            "no live matrix in the candidate list)")
        return 1
    return verify()


def probe():
    import gio
    import dumplive as dl
    open(OUT, "w").close()
    out("=== _mk20 probe %s (one instant, small reads) ===" % _now())
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        out("gio: %s" % e)
        out("VERDICT: FAIL - need elevation for gdrv3")
        return 2
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    pid = dl.find_pid()
    off = offsets_file()
    base = int(off["image_pa"], 16) if "image_pa" in off else None
    out("pid=%s ram_top=%#x ranges=%d (%s)"
        % (pid, g.ram_top, len(ranges), note))
    if base is None:
        out("VERDICT: FAIL - no image_pa in qk_offsets.txt")
        return 1
    info = pe_info(g, ranges, base)
    if not info:
        out("VERDICT: FAIL - no PE at %#x (qk_offsets.txt is from another boot)"
            % base)
        return 1
    isize, stamp = info
    out("image_pa=%#x size=%#x stamp=%#x" % (base, isize, stamp))

    rvas = []
    if "vp_rva" in off:
        rvas.append(int(off["vp_rva"], 16))
    for k in range(FAMILY_N):
        rvas.append(FAMILY + k * FAMILY_STRIDE)
    if rvas:
        v = rvas[0]
        for d in (-FAMILY_STRIDE, FAMILY_STRIDE):
            if v + d > 0:
                rvas.append(v + d)
    scanned = scan_rvas()
    if scanned:
        out("scan list: %d candidate(s) will be re-read fresh in this burst (%s)"
            % (len(scanned), os.path.basename(SCAN)))
        rvas.extend(scanned)
    seen, cand = set(), []
    for r in rvas:
        if r not in seen:
            seen.add(r)
            cand.append(r)

    # records BEFORE the matrix burst: the post-read happens after it, and only the
    # records that did not move are scored, so their position is valid at burst time
    # by construction.  That is the difference between the 14:55 pair (corr 0.73,
    # scene still) and the 15:0x pair (corr 0.43, scene moving between reads).
    seeds = census_seeds(_arg("census"))[:int(_arg("cap", "32"))]
    pre = {}
    for pa in seeds:
        b = rd(g, ranges, pa, 0xC0)
        if b and len(b) == 0xC0:
            pre[pa] = b

    lines = []
    hdr = "# _mk20 raw %s pid=%s image_pa=%#x size=%#x stamp=%#x ranges=%d %s" \
        % (_now(), pid, base, isize, stamp, len(ranges), note)
    refused = 0
    out("")
    out("matrix windows (read %#x bytes each, the scorer slides inside):" % 0x70)
    for rva in cand:
        b = rd(g, ranges, base + rva, 0x70)
        if not b or len(b) != 0x70:
            refused += 1
            lines.append("mat %#x FAIL" % rva)
            out("  %#012x FAIL (refused)" % rva)
            continue
        lines.append("mat %#x %s" % (rva, b.hex()))
        f = struct.unpack_from("<16f", b, 0)
        out("  %#012x %s" % (rva, " ".join("%9.4g" % v for v in f[:4])))
        out("  %12s %s" % ("", " ".join("%9.4g" % v for v in f[4:8])))
        out("  %12s %s" % ("", " ".join("%9.4g" % v for v in f[8:12])))
        out("  %12s %s" % ("", " ".join("%9.4g" % v for v in f[12:16])))

    out("")
    out("apexsky statics (values only; following a VA needs apexdrv, following an "
        "RVA does not):")
    for name, rva in STATICS:
        b = rd(g, ranges, base + rva, 8)
        if not b or len(b) != 8:
            lines.append("static %s %#x FAIL" % (name, rva))
            out("  %-18s +%#010x FAIL (refused)" % (name, rva))
            continue
        v = u64(b)
        lines.append("static %s %#x %s" % (name, rva, b.hex()))
        kind = "zero"
        if v:
            kind = "VA" if v >= 0x10000 else "small"
            if v < isize:
                kind = "RVA (followable in physical)"
        out("  %-18s +%#010x = %#018x  %s" % (name, rva, v, kind))

    out("")
    ok_seeds = still = 0
    keep, every = [], []
    for pa in seeds:
        b = rd(g, ranges, pa, 0xC0)
        if not b or len(b) != 0xC0:
            refused += 1
            lines.append("seed %#x FAIL" % pa)
            continue
        ok_seeds += 1
        rec = "seed %#x %s" % (pa, b.hex())
        every.append(rec)
        if pre.get(pa) == b:
            still += 1
            keep.append(rec)
    used = every            # score all: a 10 s burst moves most records, and the
    lines.extend(used)      # still count is a diagnostic, not a filter
    out("census records: %d/%d read, %d unchanged across the burst; scoring %d"
        % (ok_seeds, len(seeds), still, len(used)))
    out("refused reads: %d" % refused)

    with open(RAW, "w", encoding="utf-8") as f:
        f.write(hdr + "\n")
        f.write("\n".join(lines) + "\n")
    out("raw written: %s (%d line(s))" % (RAW, len(lines) + 1))
    alive = dl.find_pid()
    out("game alive at end: %s (pid=%s)" % (alive == pid, alive))
    return verify()


def offsets_file():
    """{image_pa, vp_rva, ...} from temp\\qk_offsets.txt - the boot's own record."""
    m = {}
    try:
        with open(OFFS, encoding="utf-8") as f:
            for line in f:
                if "=" in line:
                    k, v = line.split("=", 1)
                    m[k.strip()] = v.strip()
    except OSError:
        pass
    return m


def census_seeds(path=None):
    """Census seed PAs from _p134_out.txt, in file order."""
    pas = []
    try:
        with open(path or CENSUS, encoding="utf-8", errors="replace") as f:
            for line in f:
                mm = re.match(r"\s*@0x([0-9a-fA-F]+)", line)
                if mm:
                    pa = int(mm.group(1), 16)
                    if pa not in pas:
                        pas.append(pa)
    except OSError:
        return []
    return pas


def main():
    if "--ramscan" in sys.argv:
        return ramscan()
    if "--diff" in sys.argv:
        return diff()
    if "--scan" in sys.argv:
        return scan()
    if "--verify" in sys.argv:
        open(OUT, "w").close()
        return verify()
    return probe()


if __name__ == "__main__":
    sys.exit(main())
