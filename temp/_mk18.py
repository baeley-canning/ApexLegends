r"""_mk18.py -- Route A: table-free image_pa + live VP -> screen rects (_vp2d).

No page tables anywhere: image_pa comes from qk_image (MZ + SizeOfImage) and the
positions come from _p134's census (physical seeds), so the gdrv3 1450-law that
killed _mk17's DTB gate cannot apply here.

What it does NOT assume:
  * which of the 0xE0-strided matrix copies is the view matrix - it re-runs the
    "moves between two reads" test itself, on every candidate, and prints deltas;
  * the record shape - the census triple may be contiguous (x,y,z at +0,+4,+8) or
    strided (x,y,z at +0,+0x10,+0x20), and the height axis may be index 1 or 2
    (p134's bounds put <4000 in the middle, i.e. (x,z,y)).  All four readings are
    projected and _vp2d.verify() picks by camera-anchor / on-screen count.

Modes
  --pre     record PRE-state and exit (replaces _mk18_dev's role)
  (default) arbitrate matrix, project the seeds, one rect per record

Read-only: gio + qk_offsets.txt.  No load/DSE/service/bcdedit (R1), no reboot.
Out: temp\_mk18_pre.txt or temp\_mk18_out.txt + temp\_mk18_rects.txt (R3/R5).
Every line goes through ONE sink: print AND append (the _mk17 lesson - out() and
say() writing to different places hid a 40-minute phase).
"""
import ctypes
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
sys.path.insert(0, HERE)

import dumplive as dl   # noqa: E402
import gio              # noqa: E402
import _vp2d as vp      # noqa: E402

TMP = HERE
MINS = (-16.0, -16.0, 0.0)
MAXS = (16.0, 16.0, 72.0)
STRIDE_TOL = 1e-4


def _arg(name, default=None):
    p = "--" + name + "="
    for i, a in enumerate(sys.argv):
        if a == "--" + name and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
        if a.startswith(p):
            return a[len(p):]
    return default


PRE = "--pre" in sys.argv
OUT = _arg("out", os.path.join(TMP, "_mk18_pre.txt" if PRE else "_mk18_out.txt"))
RECTS = os.path.join(TMP, "_mk18_rects.txt")
LOG = []


def out(s=""):
    line = "" if s == "" else str(s)
    LOG.append(line)
    print(line)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def screen():
    try:
        u = ctypes.windll.user32
        return int(u.GetSystemMetrics(0)), int(u.GetSystemMetrics(1))
    except Exception:                                        # noqa: BLE001
        return 2560, 1440


def coverage(ranges, pa, n):
    for lo, hi in ranges:
        if lo <= pa and pa + n <= hi:
            return True
    return False


def read_at(g, ranges, pa, n, tries=4, why=""):
    if not coverage(ranges, pa, n):
        out("  REFUSED %#x+%#x not inside the usable interval set (%s)" % (pa, n, why))
        return None
    try:
        return dl.retry_phys(g, pa, n, tries=tries)
    except OSError as e:                                     # fault, not a hit
        out("  read fault %#x+%#x (%s): %s" % (pa, n, why, e))
        return None


def _fmt(v):
    if v is None:
        return "None"
    if isinstance(v, (int, float)):
        return "%.2f" % v
    return "(%.1f, %.1f, %.1f)" % tuple(v)


def _cam_abs(m):
    """Largest |camera| component implied by the matrix: >100 means map scale,
    ~0 means identity junk.  This is the cheapest 'am I even in a match' tell."""
    c = vp.cam_from_rows(m) or (0.0, 0.0, 0.0)
    return max(abs(x) for x in c)


def image_header(g, ranges, base):
    """(size, stamp, sections[(name, va, vsize)]) or None.  Same parse as qk_image."""
    h = read_at(g, ranges, base, 0x40, why="pe head")
    if not h or h[:2] != b"MZ":
        return None
    lf = u32(h, 0x3C)
    if lf < 0x40 or lf > 0x1000:
        return None
    nt = read_at(g, ranges, base + lf, 0x18 + 0xF0, why="nt head")
    if not nt or nt[:4] != b"PE\0\0":
        return None
    nsec, optsize = u16(nt, 6), u16(nt, 0x14)
    size = u32(nt, 0x18 + 0x38)
    stamp = u32(nt, 0x08)
    sh = read_at(g, ranges, base + lf + 0x18 + optsize, nsec * 40, why="sections")
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


def scan_matrices(g, ranges, base, dv, dsz, cap=2000, chunk=0x100000):
    """Fresh .data scan: every 16f window holding +-1.0 that is row-major and yields a
    camera.  Ranked by camera magnitude - a real VP sits at map coordinates
    (thousands of units), identity junk sits near the origin - and NOT truncated
    by address order (the first windows in .data are identity-shaped noise)."""
    found, cur, end = [], base + dv, base + dv + dsz
    while cur + chunk <= end:
        try:
            blk = dl.retry_phys(g, cur, chunk, tries=1)
        except OSError:
            blk = None
        cur += chunk
        end_n = cur - base - dv
        if (end_n >> 23) != ((end_n - chunk) >> 23):
            out("   .data scanned %d MB of %d, %d window(s)"
                % (end_n // 1048576, dsz // 1048576, len(found)))
        if not blk:
            continue
        for pat in (b"\x00\x00\x80\x3f", b"\x00\x00\x80\xbf"):
            i = blk.find(pat)
            while i >= 0:
                st = i - 60
                if st >= 0 and (st & 3) == 0 and st + 64 <= len(blk):
                    m = list(struct.unpack_from("<16f", blk, st))
                    if all(v == v and abs(v) < 1e7 for v in m) and \
                            vp.layout_of(m) and vp.cam_from_rows(m):
                        rva = cur - chunk + st - base
                        if rva not in [f[0] for f in found]:
                            found.append((rva, m))
                i = blk.find(pat, i + 4)
        if len(found) >= cap:
            break

    def rank(item):
        return -_cam_abs(item[1])
    found.sort(key=rank)
    return found[:cap]


def moved_rva(g, ranges, base, cands, wait=1.5, maxlines=10):
    """Keep the candidates whose matrix changes: a live view matrix does."""
    time.sleep(wait)
    moved, seen = [], []
    for rva, m0 in cands:
        b = read_at(g, ranges, base + rva, 64, tries=3, why="matrix re-read")
        if not b:
            continue
        m1 = list(struct.unpack("<16f", b))
        d = max(abs(x - y) for x, y in zip(m0, m1))
        if d > STRIDE_TOL:
            moved.append((d, rva, m1))
        seen.append((d, rva))
    seen.sort(reverse=True)
    for d, rva in seen[:maxlines]:
        out("   rva=%#010x max_delta=%.3f%s"
            % (rva, d, "  CHANGED" if d > STRIDE_TOL else ""))
    if len(seen) > maxlines:
        out("   ... %d candidate(s) tested, largest delta %.3f"
            % (len(seen), seen[0][0] if seen else 0.0))
    moved.sort(reverse=True)
    return moved


def live_find(g, ranges, base, dv, dsz, budget=0.0, poll=5.0):
    """Find a live view matrix, waiting up to `budget` s for one that is both
    world-scale and moving.  budget=0 does exactly one pass (no waiting).

    The .data block holding the VP is transient: at 12:52 it moved by 33k per
    1.5 s, by 13:07 the same region was static identity junk (match over).  So the
    caller may start this BEFORE the match starts and let it poll.
    Returns (candidates, moved, moved_ok)."""
    t0 = time.time()
    while True:
        cands = scan_matrices(g, ranges, base, dv, dsz)
        world = [c for c in cands if _cam_abs(c[1]) >= 100.0]
        out("  scan t=%.0fs windows=%d world-scale=%d"
            % (time.time() - t0, len(cands), len(world)))
        if cands:
            # motion on ALL windows: restricting the test to the world-scale few
            # answers "did those four move", not "is the VP in .data at all".
            mv = moved_rva(g, ranges, base, cands[:500])
            if mv:
                wset = set(rva for rva, _ in world)
                mw = [x for x in mv if x[1] in wset]
                out("  %d window(s) moved in 1.5s, %d of them world-scale"
                    % (len(mv), len(mw)))
                return cands, (mw or mv), True
            out("  no window in .data changed in 1.5s "
                "(camera static, or the VP is not in .data)")
        else:
            out("  no matrix-shaped window in .data at all")
        if time.time() - t0 >= budget:
            return cands, [], False
        time.sleep(poll)


def log_cands(path, base):
    """rva list from a qk_image --data log (it already found + ranked them)."""
    rvas, cur = [], None
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                t = line.strip()
                if t.startswith("chosen image_pa="):
                    cur = int(t.split("=")[1].split()[0], 16)
                elif t.startswith("rva=") and cur == base:
                    rva = int(t.split("=")[1].split()[0], 16)
                    if rva not in rvas:
                        rvas.append(rva)
    except OSError:
        return []
    return rvas


def seeds_from(path):
    """SEED lines (p134's coherent-stop set); fall back to COH-marked @addr lines."""
    s, addr = [], []
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                t = line.strip()
                if t.startswith("SEED "):
                    s.append(int(t.split()[1], 0))
                elif t.startswith("@0x"):
                    addr.append(int(t.split()[0][1:], 16))
    except OSError:
        return []
    return s or addr


def read_triple(g, ranges, pa):
    b = read_at(g, ranges, pa, 0x30, tries=4, why="seed record")
    if not b or len(b) < 0x24:
        return None
    f = struct.unpack_from("<12f", b, 0)
    return {"contig": (f[0], f[1], f[2]), "strided": (f[0], f[4], f[8])}


def pre(g, ranges, pid):
    out("=== _mk18 PRE %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
    out("game pid=%s find_pid=%s" % (pid, dl.find_pid()))
    out("ram_top=%#x ranges=%d" % (g.ram_top, len(ranges)))
    for lo, hi in ranges:
        out("   %#012x .. %#012x  (%#x)" % (lo, hi, hi - lo))
    ctrl = g.read_phys(0x1000, 16)
    out("control read 0x1000 len=%d %s" % (len(ctrl) if ctrl else 0,
                                            ctrl.hex() if ctrl else ""))
    p = os.path.join(TMP, "qk_offsets.txt")
    try:
        st = os.stat(p)
        with open(p, encoding="utf-8") as f:
            body = f.read().strip().replace("\n", " | ")
        out("qk_offsets.txt mtime=%s body=%s"
            % (time.strftime("%H:%M:%S", time.localtime(st.st_mtime)), body))
    except OSError as e:
        out("qk_offsets.txt absent (%s)" % e)
    out("RESULT: device=open pid=%s" % pid)
    out("VERDICT: %s" % ("PASS - pre-state recorded" if pid
                          else "PARTIAL - game not running (R9)"))
    return 0


def _base_from(path):
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if line.startswith("image_pa="):
                    return int(line.split("=", 1)[1], 16)
    except OSError:
        return None
    return None


def run(g, ranges, pid):
    out("=== _mk18 %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
    W, H = screen()
    out("screen=%dx%d" % (W, H))
    moved_ok = True
    off_path = _arg("offsets", os.path.join(TMP, "qk_offsets.txt"))
    base = _arg("image-pa")
    base = int(base, 0) if base else _base_from(off_path)
    if base is None:
        out("RESULT: no image_pa")
        out("VERDICT: FAIL - run qk_image --data --watch first")
        return 1
    hdr = image_header(g, ranges, base)
    if not hdr:
        out("RESULT: image_pa=%#x unreadable" % base)
        out("VERDICT: FAIL - no PE at that base (stale qk_offsets.txt?)")
        return 1
    size, stamp, secs = hdr
    out("image_pa=%#012x size=%#x stamp=%#010x sections=%d"
        % (base, size, stamp, len(secs)))
    dv = dsz = None
    for name, va, vs in secs:
        if name == ".data":
            dv, dsz = va, vs
    if dv is None:
        out("RESULT: image_pa=%#x has no .data" % base)
        out("VERDICT: FAIL - not the game image")
        return 1
    out(".data va=%#x size=%#x (%d MB)" % (dv, dsz, dsz // 1048576))

    img_log = _arg("img", os.path.join(TMP, "_mk18_img.txt"))
    if "--scan" in sys.argv:
        rvas = []                                   # ignore the cached RVA list
        out("--scan given: ignoring the qk_image candidate list")
    else:
        rvas = log_cands(img_log, base)
    if rvas:
        out("candidates from %s: %d (re-reading each)"
            % (os.path.basename(img_log), len(rvas)))
        got = []
        for rva in rvas:
            b = read_at(g, ranges, base + rva, 64, tries=3, why="matrix")
            if not b:
                continue
            m = list(struct.unpack("<16f", b))
            got.append((rva, m))
            lay0 = vp.layout_of(m)
            out("   rva=%#010x layout=%s cam=%s"
                % (rva, lay0, _fmt(vp.cam_from_rows(m))))
            if not lay0:
                out("      raw %s" % " ".join("%.4g" % x for x in m))
        if not got:
            out("RESULT: %d candidates, 0 readable" % len(rvas))
            out("VERDICT: FAIL - matrix reads refused")
            return 1
        mv = moved_rva(g, ranges, base, got)
        if not mv:
            out("0 of %d candidates moved in 1.5s - falling back to the anchor "
                "test, verdict can be PARTIAL at best" % len(got))
            moved_ok = False
            mv = [(0.0, rva, m) for rva, m in got]
    else:
        out("no rva lines for this base in the log - scanning .data myself")
        try:
            budget = float(_arg("wait-live", "0"))
        except ValueError:
            budget = 0.0
        if budget:
            out("waiting up to %.0fs for a live (world-scale, moving) view matrix"
                % budget)
        cands, mv, moved_ok = live_find(g, ranges, base, dv, dsz, budget)
        out("scan found %d candidate(s), largest |cam|=%.1f"
            % (len(cands), _cam_abs(cands[0][1]) if cands else 0.0))
        for rva, m in cands[:12]:
            out("   scan rva=%#010x layout=%s cam=%s"
                % (rva, vp.layout_of(m), _fmt(vp.cam_from_rows(m))))
        if not cands:
            out("RESULT: no view-matrix-shaped window in .data")
            out("VERDICT: FAIL - matrix not found")
            return 1
        if not mv:
            out("no moving world-scale candidate - falling back to the anchor "
                "test, verdict can be PARTIAL at best")
            mv = [(0.0, rva, m) for rva, m in cands[:24]]
    out("live matrix rva=%#010x (delta=%.1f), %d moving candidate(s), moved_ok=%s"
        % (mv[0][1], mv[0][0], len(mv), moved_ok))
    pool = [(rva, m) for _, rva, m in mv]
    if not moved_ok:
        pool = pool[:24]                # only the world-scale end of the ranking
        out("anchor-only arbitration over the top %d candidate(s)" % len(pool))

    seed_path = _arg("seeds", os.path.join(TMP, "_p134_out.txt"))
    seeds = seeds_from(seed_path)
    out("seeds=%d from %s" % (len(seeds), os.path.basename(seed_path)))
    if not seeds:
        out("RESULT: live rva=%#x layout=%s, no census seeds"
            % (pool[0][0], vp.layout_of(pool[0][1])))
        out("VERDICT: PARTIAL - matrix live but no records to project (run _p134)")
        return 2

    recs = []
    for pa in seeds:
        t = read_triple(g, ranges, pa)
        if t:
            recs.append((pa, t))
    out("records readable=%d/%d" % (len(recs), len(seeds)))
    if not recs:
        out("RESULT: seeds=%d readable=0" % len(seeds))
        out("VERDICT: PARTIAL - seeds unreadable (re-run _p134; pools move)")
        return 2

    best = None
    pi = -1
    for rva, m in pool:
        pi += 1
        lay = vp.layout_of(m)
        if not lay:
            out("  skip rva=%#010x (not row-major)" % rva)
            continue
        for shape in ("contig", "strided"):
            for zax in (2, 1):
                rows = []
                for pa, t in recs:
                    a, b, c = t[shape]
                    org = (a, b, c) if zax == 2 else (a, c, b)
                    rows.append({"org": org,
                                 "rect": vp.rect_for(m, org, MINS, MAXS, W, H,
                                                      "row", wsrc=lay)})
                v = vp.verify(rows, m, "row")
                # aspect FIRST: the census carries junk triples near the origin, so
                # verify()'s min-distance anchor is pinned at ~1.7 by a decoy and
                # cannot discriminate.  Human-ish rect shapes can.
                key = (-v["aspect"],
                       v["anchor"] if v["anchor"] is not None else 9e9,
                       -v["on"])
                if pi < 6 or best is None or key < best[0]:
                    out("  try rva=%#010x layout=%s shape=%-7s zax=%d on=%d/%d "
                        "aspect=%d local=%d anchor=%s"
                        % (rva, lay, shape, zax, v["on"], v["n"], v["aspect"],
                           v["local"], _fmt(v["anchor"])))
                if best is None or key < best[0]:
                    best = (key, rva, lay, shape, zax, rows, v)

    if best is None:
        out("RESULT: no row-major candidate survived")
        out("VERDICT: FAIL - matrix not row-major in any layout")
        return 1
    _, rva, lay, shape, zax, rows, v = best
    out("CHOSEN rva=%#010x layout=%s shape=%s zax=%d" % (rva, lay, shape, zax))
    with open(RECTS, "w", encoding="utf-8") as f:
        f.write("# _mk18 %s  rva=%#x layout=%s shape=%s zax=%d screen=%dx%d\n"
                % (time.strftime("%Y-%m-%d %H:%M:%S"), rva, lay, shape, zax, W, H))
        for (pa, _), r in zip(recs, rows):
            rr = r["rect"]
            if not rr:
                f.write("%#011x off-screen\n" % pa)
                continue
            f.write("%#011x %s x0=%7.1f y0=%7.1f x1=%7.1f y1=%7.1f w=%6.1f "
                    "h=%6.1f d=%7.0f corners=%d\n"
                    % (pa, r["org"], rr["x0"], rr["y0"], rr["x1"], rr["y1"],
                       rr["x1"] - rr["x0"], rr["y1"] - rr["y0"], rr["depth"],
                       rr["corners"]))
    out("rects written: %s" % RECTS)
    alive = dl.find_pid()
    anchor = v["anchor"]
    out("game alive at end: %s (pid=%s)" % (alive == pid, alive))
    ok = (v["on"] >= 3 and anchor is not None and anchor <= 128.0 and alive == pid
          and v["aspect"] >= 3 and v["aspect"] * 2 >= v["on"])
    geo = ok
    ok = ok and moved_ok
    out("CAMERA derived=%s  aspect majority=%d/%d"
        % ("yes" if anchor is not None else "no", v["aspect"], v["on"]))
    out("RESULT: rva=%#x layout=%s on=%d/%d aspect=%d anchor=%s local=%d moved_ok=%s"
        % (rva, lay, v["on"], v["n"], v["aspect"], _fmt(anchor), v["local"], moved_ok))
    if ok:
        out("VERDICT: PASS - %d on-screen rect(s), camera anchor %.1f units"
            % (v["on"], anchor))
    elif geo:
        out("VERDICT: PARTIAL - geometry fits (on=%d anchor=%.1f) but no candidate "
            "moved, so liveness is unproven (R9)" % (v["on"], anchor))
    elif alive != pid:
        out("VERDICT: PARTIAL - game died during the run (R9)")
    else:
        out("VERDICT: FAIL - on=%d anchor=%s (need >=3 rects inside 128 units)"
            % (v["on"], _fmt(anchor)))
    return 0 if ok else 1


def main():
    open(OUT, "w").close()
    try:
        return _main()
    except Exception:                                        # noqa: BLE001
        import traceback
        out("EXCEPTION:")
        for line in traceback.format_exc().rstrip().splitlines():
            out("  " + line)
        out("RESULT: crashed")
        out("VERDICT: FAIL - unhandled exception, see EXCEPTION block")
        return 3


def _main():
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        out("gio: %s" % e)
        out("RESULT: device=closed")
        out("VERDICT: FAIL - need elevation for gdrv3")
        return 2
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    pid = dl.find_pid()
    if PRE:
        return pre(g, ranges, pid)
    out("ram_top=%#x ranges=%d (%s) pid=%s" % (g.ram_top, len(ranges), note, pid))
    if pid is None:
        out("RESULT: game_pid=none")
        out("VERDICT: PARTIAL - game not running (R9)")
        return 2
    return run(g, ranges, pid)


if __name__ == "__main__":
    sys.exit(main())



