"""basehunt.py -- brute-force the kernel linear-map base B from the decoy flink.

c29 measured the layout on this boot off a real svchost EPROCESS: the object
base sits at page offset 0x80, dispatcher type 3 at that base, UniqueProcessId
+0x1D0, a LIST_ENTRY at +0x1D8 whose two values end 0x258 and 0x260, and
ImageFileName +0x338.  So 0x258 is the *value* lane (the neighbour's own
phase+field offset), never a field offset -- a LIST_ENTRY points at the same
field in the neighbour.  p44d shows the decoys copy that shape at phase 0xC0
with the same +0x1D8 pair, which is why reciprocity can gate on it.

The only assumption is a linear map  PA = VA - B  with B random per boot.
B is constrained: PA must stay below RAM top, so B lies in (VA - ram_top, VA).
Every page-aligned B in that window is tried; a candidate page is accepted only
when all of these hold on the mapped page:

  * type 3 at the object base, pid +0x1D0 in range, printable name +0x338,
  * a KVA pair at +0x1D8 with the two value lanes 0x258/0x260,
  * reciprocal proof: the decoy's own VA under the same B must still read as a
    live EPROCESS whose +0x1d8/+0x1e0 equal the two pointers.

RAM is read in 64 KiB windows (one ioctl per 16 pages instead of 16) with a
heartbeat, a checkpoint line and --from / --max-s resume, because this host
bugchecks (0x124) when a probe runs long.  Dead spans answer Errno 1450 page
after page (p44f smoke: the low ~600 MB) and are hopped over in 2 MiB strides
instead of being retried per page.  Accepted B -> walk the list both ways for a
live pid 0x1570 and dump the image.  READ-ONLY, nothing to restore.
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402
import dumplive as dl  # noqa: E402

ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_OUT", "p44f_base.txt"))
PROG = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_PROG", "p44f_progress.txt"))
DECOY = [0x2481D60C0, 0x62BC6E190, 0x7DE10FBF0]
LINK = 0x2481D60C0                      # decoy PA; its page offset is 0xC0
OBJ_PAIR = 0x1D8                        # LIST_ENTRY pair (c29, measured)
PAIR_ALT = 0x258                        # same field on a page-aligned object
OBJ_PID = 0x1D0
OBJ_NAME = 0x338
LANE_FL = 0x258                         # value lanes: target phase + pair offset
LANE_BL = 0x260
NODE_FL = 0xFFFFA401B25A5258            # decoy flink target, a real neighbour
NODE_BL = 0xFFFFA401B7EA0258            # decoy blink target
WIN = 0x10000                           # 64 KiB: one ioctl per 16 pages
PID = int(os.environ.get("DUMP_PID", "0x1570"), 0)   # target pid (moves per launch)
HOP_CAP = 400
LOG = []


def log(s):
    LOG.append(s)
    print(s)


def prog(s):
    try:
        with open(PROG, "a", encoding="utf-8") as f:
            f.write("%s  %s\n" % (time.strftime("%H:%M:%S"), s))
            f.flush()
            os.fsync(f.fileno())
    except OSError:
        pass


def shape_at(p, o, pair):
    """Neighbour-shaped EPROCESS at page offset `o` -> (pid, fl, bl) or None.

    `pair` is the LIST_ENTRY offset inside the object; the two values must point
    at the same field of a neighbour, i.e. end on the value lanes -- that check,
    not the phase guess, is what a random page full of KVAs cannot fake.
    """
    if o + OBJ_NAME + 15 > 0x1000 or p[o] != 3:
        return None
    pid = struct.unpack_from("<I", p, o + OBJ_PID)[0]
    if not (0 < pid <= 0x100000):
        return None
    fl, bl = struct.unpack_from("<QQ", p, o + pair)
    if fl >> 48 != 0xFFFF or bl >> 48 != 0xFFFF:
        return None
    # Both values end on the same lane: Blink points at the previous node's
    # Flink field, so it is the same offset in the neighbour (c29 measured it).
    if (fl & 0xFFF) != o + pair or (bl & 0xFFF) != o + pair:
        return None
    nm = p[o + OBJ_NAME:o + OBJ_NAME + 15].split(b"\x00", 1)[0]
    if not (1 <= len(nm) <= 15) or not all(0x20 <= c < 0x7F for c in nm):
        return None
    return pid, fl, bl

def wr(code, verdict):
    log("VERDICT: %s" % verdict)
    open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
    return code


def decoy_read(g, b, pa):
    """Read the decoy through candidate B and verify reciprocity.

    The decoy is validated at its *own* phase 0xC0 (p44d), and the two values it
    returns are compared against the walk starts p44d recorded.
    """
    va = b + pa
    try:
        page = g.read_phys(va & ~0xFFF, 0x1000)
    except OSError:
        return None
    o = va & 0xFFF
    if page[o] != 3:
        return None
    pid = struct.unpack_from("<I", page, o + OBJ_PID)[0]
    nm = page[o + OBJ_NAME:o + OBJ_NAME + 15]
    if pid != PID or not nm.startswith(b"r5apex"):
        return None
    return struct.unpack_from("<QQ", page, o + OBJ_PAIR)


def skip_dead(g, pa, rhi, step=0x200000):
    """Probe forward in 2 MiB strides until a page reads -> (pa, probes).

    p44f smoke: the low ~600 MB answers Errno 1450 (ERROR_NO_SYSTEM_RESOURCES)
    page after page while 0x80000000, 0x100000000 and 0x1b25a5000 read fine, so
    the hole is dead, not the transport -- and 150k dead pages must not cost
    150k ioctls.  Returns (rhi, probes) when the rest of the range is dead.
    """
    probes = 0
    while pa < rhi:
        probes += 1
        try:
            g.read_phys(pa, 0x1000)
            return pa, probes
        except OSError:
            pa = (pa + step) & ~0xFFF
    return rhi, probes

def hunt(g, ranges, va, ram_top, dry=0, start=None, budget=None):
    """Try every page-aligned B in the window -> (B, resume_pa, why).

    `why` is ok / dry / budget / none.  WIN bytes per ioctl: 16 candidate pages
    for one call, shape_at() rejects them without any further read, and only a
    shape hit pays for the decoy reciprocity.  A faulted window is retried page
    by page so one poisoned page cannot cost its 15 neighbours, and a mostly
    dead window hands the loop to skip_dead().  Every 64 windows a durable CKPT
    line names the next PA, so a 0x124 reboot resumes with start=<pa>.
    """
    page = va & ~0xFFF
    hi_page = max(page, NODE_BL & ~0xFFF)
    lo_page = min(page, NODE_BL & ~0xFFF)
    lo = hi_page - ram_top
    if lo < 0xFFFFA40000000000:
        lo = 0xFFFFA40000000000
    lo = (lo + 0xFFF) & ~0xFFF
    if lo > lo_page:
        lo = lo_page
    pa_max = hi_page - lo
    log("window B=%#x..%#x  pa_max=%#x  %d pages  dry=%d"
        % (lo, hi_page, pa_max, pa_max // 0x1000, dry))
    # pa_max is itself a valid candidate, so the exclusive plan bound sits one
    # page above it -- the flink target lands exactly on it when B == lo.
    plan = [(a, min(b, pa_max + 0x1000)) for a, b in ranges if a <= pa_max]
    t0 = time.perf_counter()
    tried = shapes = wins = 0
    for rlo, rhi in plan:
        rt = time.perf_counter()
        pa = rlo
        while pa < rhi:
            if start is not None and pa < start:
                pa += WIN
                continue
            n = min(WIN, rhi - pa)
            wins += 1
            if wins % 64 == 0:
                prog("CKPT next=%#x tried=%d shapes=%d %.0fs"
                     % (pa + n, tried, shapes, time.perf_counter() - t0))
                if wins % 256 == 0:
                    log("  ... pa=%#x tried=%d shapes=%d %.1fs"
                        % (pa, tried, shapes, time.perf_counter() - t0))
            if budget and time.perf_counter() - t0 > budget:
                prog("BUDGET next=%#x tried=%d shapes=%d" % (pa, tried, shapes))
                log("budget %.1fs, stop at pa=%#x" % (time.perf_counter() - t0, pa))
                return None, pa, "budget"
            try:
                buf = g.read_phys(pa, n)
            except OSError as e:
                prog("FAULT pa=%#x n=%#x %s" % (pa, n, e))
                buf = None
            pages = []
            if buf is None:
                for k in range(0, n, 0x1000):
                    try:
                        pages.append((pa + k, g.read_phys(pa + k, 0x1000)))
                    except OSError:
                        pass
                lost = n // 0x1000 - len(pages)
                if lost:
                    prog("BADPAGE %#x of %#x dead at %#x"
                         % (lost, n // 0x1000, pa))
            else:
                pages = [(pa + k, buf[k:k + 0x1000]) for k in range(0, n, 0x1000)]
            for ppa, p in pages:
                tried += 1
                if len(p) < 0x400:                  # short/torn page read
                    continue
                hit = None
                for o, pair in ((0x080, OBJ_PAIR), (0x000, PAIR_ALT)):
                    s = shape_at(p, o, pair)
                    if s:
                        hit = (o, pair, s)
                        break
                if not hit:
                    continue
                o, pair, s = hit
                shapes += 1
                log("shape pa=%#x o=%#x pid=%#x name=%r"
                    % (ppa, o, s[0], p[o + OBJ_NAME:o + OBJ_NAME + 15]))
                for node in (NODE_FL, NODE_BL):
                    b = (node - (o + pair)) - ppa
                    tag = "FL" if node == NODE_FL else "BL"
                    r = decoy_read(g, b, LINK)
                    if not r:
                        log("  b=%#x (%s) reciprocity failed" % (b, tag))
                        continue
                    if r[0] != NODE_FL or r[1] != NODE_BL:
                        log("  b=%#x (%s) WARN decoy pair %#x/%#x != %#x/%#x"
                            % (b, tag, r[0], r[1], NODE_FL, NODE_BL))
                        if r[0] != NODE_FL and r[1] != NODE_BL:
                            log("  neither half matches, rejected")
                        continue
                    log("  ACCEPT B=%#x via %s pa=%#x decoy pair intact"
                        % (b, tag, ppa))
                    prog("ACCEPT b=%#x via=%s shapes=%d" % (b, tag, shapes))
                    log("  tried=%d shapes=%d %.1fs"
                        % (tried, shapes, time.perf_counter() - t0))
                    return b, None, "ok"
                if dry and shapes >= dry:
                    log("dry: %d shapes, stopping" % shapes)
                    prog("DRY stop at pa=%#x shapes=%d" % (ppa, shapes))
                    return None, ppa, "dry"
            pa += n
            if len(pages) * 2 < n // 0x1000:        # mostly-dead window -> hop over
                here = pa
                nxt, probes = skip_dead(g, pa, rhi)
                prog("SKIP %#x..%#x %#x probes=%d"
                     % (here, nxt, nxt - here, probes))
                log("  dead %#x..%#x skipped (%d probes)" % (here, nxt, probes))
                pa = nxt
        log("range %#x..%#x done %.1fs" % (rlo, rhi, time.perf_counter() - rt))
    log("no candidate  tried=%d shapes=%d %.1fs"
        % (tried, shapes, time.perf_counter() - t0))
    return None, None, "none"


def hop(g, b, va, seen):
    """VA (a link node) -> (pid, base_pa, fl, bl, name) for an EPROCESS, or None.

    The node sits at base+pair, so the base offset is the node's own page offset
    minus the pair offset.  Both pairs are tried: 0x1D8 is the measured live
    pair and 0x258 the page-aligned variant -- which also lets the walk step
    onto a decoy (phase 0xC0, pair 0x1D8) instead of stalling on it.
    """
    page = (va - b) & ~0xFFF
    off = (va - b) & 0xFFF
    if not g.is_ram(page):
        return None
    try:
        p = g.read_phys(page, 0x1000)
    except OSError:
        return None
    for pair in (OBJ_PAIR, PAIR_ALT):
        o = off - pair
        if o < 0 or o + OBJ_NAME + 15 > 0x1000 or p[o] != 3:
            continue
        base = page + o
        if base in seen:
            continue
        pid = struct.unpack_from("<I", p, o + OBJ_PID)[0]
        if not (0 < pid <= 0x100000):
            continue
        fl, bl = struct.unpack_from("<QQ", p, o + pair)
        if (fl & 0xFFF) != o + pair or (bl & 0xFFF) != o + pair:
            continue
        seen.add(base)
        return pid, base, fl, bl, p[o + OBJ_NAME:o + OBJ_NAME + 15]
    return None


def walk(g, b, start_va, seen, tag):
    """Follow one direction; collect (pid, base, name) until HOP_CAP or a repeat."""
    va = start_va
    out = []
    for i in range(HOP_CAP):
        h = hop(g, b, va, seen)
        if not h:
            out.append(("dead", va))
            break
        pid, base, fl, bl, nm = h
        out.append((pid, base, nm))
        prog("%s hop%d pid=%#x base=%#x name=%r" % (tag, i, pid, base, nm))
        nxt = fl if tag == "FL" else bl
        if nxt == start_va:
            out.append(("ring", nxt))
            break
        va = nxt
    return out


def main():
    sys.argv = ["basehunt"] + sys.argv[1:]
    dry = 0
    start = None
    budget = 25.0
    for a in sys.argv[1:]:
        if a == "--dry":
            dry = 1
        elif a.startswith("--dry="):
            dry = int(a.split("=", 1)[1], 0)
        elif a.startswith("--from="):
            start = int(a.split("=", 1)[1], 0)
        elif a.startswith("--max-s="):
            budget = float(a.split("=", 1)[1])
    if not dl.elevation():
        return wr(3, "NOT_ELEVATED")
    log("basehunt  %s  dry=%d from=%s max-s=%.0f"
        % (time.strftime("%Y-%m-%d %H:%M:%S"), dry, start, budget))
    try:
        g = gio.Gio(chunk=dl.SCAN_CHUNK)
    except OSError as e:
        log("FATAL: %s" % e)
        return wr(2, "FATAL no transport")
    try:
        ranges, note = dl.usable_ranges(g.ram_top, None, None)
        log("RAMTOP %#x %s ranges=%d" % (g.ram_top, note, len(ranges)))
        b, resume, why = hunt(g, ranges, NODE_FL, g.ram_top,
                              dry=dry, start=start, budget=budget)
        if b is None:
            if why == "budget":
                return wr(0, "PARTIAL resume_pa=%#x" % resume)
            if why == "dry":
                return wr(0, "DRY_OK stopped_after_shapes resume_pa=%#x" % resume)
            return wr(1, "NO_BASE")
        if dry:
            return wr(0, "DRY_ACCEPT b=%#x" % b)
        seen = set()
        fl = walk(g, b, NODE_FL, seen, "FL")
        bl = walk(g, b, NODE_BL, seen, "BL")
        log("FL %d hops, BL %d hops" % (len(fl), len(bl)))
        targets = [x for x in fl + bl if isinstance(x[0], int) and x[0] == PID]
        log("pid %#x hops: %d" % (PID, len(targets)))
        import ctypes
        buf = ctypes.create_string_buffer(0x2000000)
        st = dl.Stats()
        for pid, base, nm in targets:
            try:
                p = g.read_phys(base, 0x1000)
            except OSError:
                log("  base %#x unreadable" % base)
                continue
            dtb = struct.unpack_from("<Q", p, 0x28)[0] & dl.MASK
            log("  target base=%#x dtb=%#x name=%r" % (base, dtb, nm))
            if not g.is_ram(dtb):
                log("   dtb outside RAM")
                continue
            why2 = dl.probe_dtb(g, dtb)
            log("   probe: %s" % why2)
            if "pdpt ram" not in why2:
                log("   dtb does not page")
                continue
            mz = dl.find_mz(g, dtb)
            if not mz:
                log("   no MZ")
                continue
            mva, meta = mz
            log("   MZ va=%#x size=%#x secs=%d" % (mva, meta["size"], len(meta["secs"])))
            w = dl.Walk(g, dtb)
            for name, sva, vsize in meta["secs"]:
                log("   sec %-8s va=%#x size=%#x" % (name, sva, vsize))
                dl.dump_range(g, w, buf, mva, sva, min(vsize, 0x2000000), st)
            log("   read=%#x zero=%#x fail=%#x" % (st.read, st.zero, st.fail))
            path = os.path.join(ROOT, "_ritual", "p44f_image.bin")
            open(path, "wb").write(bytes(buf))
            import hashlib
            h = hashlib.sha256(bytes(buf)).hexdigest()
            log("   dump %s sha256=%s" % (path, h))
            return wr(0, "DUMP_OK pid=%#x base=%#x dtb=%#x va=%#x sha256=%s"
                      % (PID, base, dtb, mva, h))
        return wr(1, "NO_LIVE_OBJECT fl=%d bl=%d" % (len(fl), len(bl)))
    finally:
        g.close()


if __name__ == "__main__":
    sys.exit(main())
