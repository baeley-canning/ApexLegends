"""basehunt.py -- brute-force the kernel linear-map base B for the decoy flink.

p44d settled the geometry against real bytes: a decoy sits at page offset 0xC0,
types 3 at its base, and carries its fake LIST_ENTRY at decoy+0x1d8.  Those two
values end on lane 0x258, i.e. they point at *real* neighbours whose base is
page aligned and whose live ActiveProcessLinks entry is at base+0x258.  p44c
proves the phase matters: with the guessed B, pa = flink - 0x1d8 reads type 255
and pa = flink - 0x258 is the neighbour.  chainprobe's +0x080 fingerprint and
basehunt's old -0x1d8 hop both used the wrong lane; both are corrected here.

The only assumption is a linear map  PA = VA - B  with B random per boot.
B is constrained: PA must stay below RAM top, so B lies in (VA - ram_top, VA).
Every page-aligned B in that window is tried; a candidate is accepted only when
all of these hold on the mapped page:

  * byte +0x000 == 3, pid +0x1d0 in range, printable ImageFileName +0x338,
  * a KVA pair on lanes 0x258/0x260,
  * reciprocal proof: the decoy's own VA under the same B must still read as a
    live EPROCESS whose +0x1d8/+0x1e0 equal the two pointers.

RAM is read in 64 KiB windows (one ioctl per 16 pages instead of 16) so the scan
stays cheap enough to survive EAC.  A faulted window is retried page by page so
one poisoned page cannot cost its 15 neighbours; a heartbeat every 256 windows
and a durable CKPT line (the next PA to read) every 64 let a 0x124 reboot resume
with --from=<pa> instead of from zero.  --max-s=<s> bounds a run, --dry[=N]
stops after N shape hits.  Accepted B -> walk the list both ways for a live pid
0x1570 and dump the image.  READ-ONLY, nothing to restore.
"""
import os
import struct
import subprocess
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
DECOY_LANE = 0x1D8                      # fake LIST_ENTRY inside the decoy
OBJ_LINK = 0x258                        # live ActiveProcessLinks entry (p44d)
OBJ_PID = 0x1D0
OBJ_NAME = 0x338
NODE_FL = 0xFFFFA401B25A5258            # decoy flink target, a real neighbour
NODE_BL = 0xFFFFA401B7EA0258            # decoy blink target
WIN = 0x10000                           # 64 KiB: one ioctl per 16 pages
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


def shape(p):
    """Real neighbour EPROCESS at page offset 0 -> (pid, fl, bl) or None.

    p44d: the base is page aligned and the live links are at +0x258, so the
    object starts at p[0].  The 0x080 phase chainprobe guessed is measured
    against the decoy itself (offset 0xC0), not against the neighbours.
    """
    if p[0] != 3:
        return None
    pid = struct.unpack_from("<I", p, OBJ_PID)[0]
    if not (0 < pid <= 0x100000):
        return None
    fl, bl = struct.unpack_from("<QQ", p, OBJ_LINK)
    if fl >> 48 != 0xFFFF or bl >> 48 != 0xFFFF:
        return None
    if (fl & 0xFFF) != OBJ_LINK or (bl & 0xFFF) != OBJ_LINK + 8:
        return None
    nm = p[OBJ_NAME:OBJ_NAME + 15]
    if nm == b"\x00" * 15 or not all(0x20 <= c < 0x7F for c in nm):
        return None
    return pid, fl, bl


def wr(code, verdict):
    log("VERDICT: %s" % verdict)
    open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
    return code


def decoy_read(g, b, pa):
    """Read the decoy through candidate B and verify reciprocity.

    The decoy is validated at its *own* phase 0xC0 (p44d), and the two values
    it returns are compared against the walk starts p44d recorded.
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
    if pid != 0x1570 or not nm.startswith(b"r5apex"):
        return None
    return struct.unpack_from("<QQ", page, o + DECOY_LANE)


def hunt(g, ranges, va, ram_top, dry=0, start=None, budget=None):
    """Try every page-aligned B in the window -> (B, resume_pa, why).

    `why` is ok / dry / budget / none.  WIN bytes per ioctl: 16 candidate pages
    for one call, shape() rejects them without any further read, and only a
    shape hit pays for the decoy reciprocity.  A faulted window is retried page
    by page so one poisoned page cannot cost its 15 neighbours.  Every 64
    windows a durable CKPT line names the next PA, so a 0x124 reboot resumes
    with start=<pa> instead of from zero.
    """
    page = va & ~0xFFF
    lo = page - ram_top
    if lo < 0xFFFFA40000000000:
        lo = 0xFFFFA40000000000
    lo = (lo + 0xFFF) & ~0xFFF
    pa_max = page - lo
    log("window B=%#x..%#x  pa_max=%#x  %d pages  dry=%d"
        % (lo, page, pa_max, (page - lo) // 0x1000, dry))
    plan = [(a, min(b, pa_max)) for a, b in ranges if a < pa_max]
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
            except OSError:
                prog("FAULT pa=%#x n=%#x" % (pa, n))
                buf = None
            if buf is None:
                pages = []
                for k in range(0, n, 0x1000):
                    try:
                        pages.append((pa + k, g.read_phys(pa + k, 0x1000)))
                    except OSError:
                        prog("BADPAGE pa=%#x" % (pa + k))
            else:
                pages = [(pa + k, buf[k:k + 0x1000]) for k in range(0, n, 0x1000)]
            for ppa, p in pages:
                tried += 1
                if len(p) < 0x400:                  # short/torn page read
                    continue
                s = shape(p)
                if not s:
                    continue
                shapes += 1
                b = page - ppa
                log("shape B=%#x pa=%#x pid=%#x name=%r"
                    % (b, ppa, s[0], p[OBJ_NAME:OBJ_NAME + 15]))
                r = decoy_read(g, b, LINK)
                if not r:
                    log("  reciprocity failed")
                elif r[0] == NODE_FL and r[1] == NODE_BL:
                    log("  ACCEPT B=%#x decoy flink=%#x blink=%#x" % (b, r[0], r[1]))
                    prog("ACCEPT b=%#x shapes=%d" % (b, shapes))
                    log("  tried=%d shapes=%d %.1fs"
                        % (tried, shapes, time.perf_counter() - t0))
                    return b, None, "ok"
                else:
                    log("  WARN decoy pair %#x/%#x != %#x/%#x"
                        % (r[0], r[1], NODE_FL, NODE_BL))
                    if r[0] != NODE_FL and r[1] != NODE_BL:
                        log("  neither half matches, rejected")
                if dry and shapes >= dry:
                    log("dry: %d shapes, stopping" % shapes)
                    prog("DRY stop at pa=%#x shapes=%d" % (ppa, shapes))
                    return None, ppa, "dry"
            pa += n
        log("range %#x..%#x done %.1fs" % (rlo, rhi, time.perf_counter() - rt))
    log("no candidate  tried=%d shapes=%d %.1fs"
        % (tried, shapes, time.perf_counter() - t0))
    return None, None, "none"


def hop(g, b, va, seen):
    """VA -> (pid, base_pa, fl, bl, name) for a list node, or None.

    p44d: the node VA is base+0x258, so the object starts at pa-0x258 -- NOT the
    -0x1d8 lane the decoy's fake LINK_ENTRY sits on.
    """
    base = va - b - OBJ_LINK
    o = base & 0xFFF
    if base in seen or not g.is_ram(base) or o > 0xCA0:
        return None
    seen.add(base)
    try:
        p = g.read_phys(base - o, 0x1000)
    except OSError:
        return None
    if p[o] != 3:
        return None
    pid = struct.unpack_from("<I", p, o + OBJ_PID)[0]
    fl, bl = struct.unpack_from("<QQ", p, o + OBJ_LINK)
    return pid, base, fl, bl, p[o + OBJ_NAME:o + OBJ_NAME + 15]


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
    budget = None
    for a in sys.argv[1:]:
        if a == "--dry":
            dry = 1
        elif a.startswith("--dry="):
            dry = int(a.split("=", 1)[1], 0)
        elif a.startswith("--from="):
            start = int(a.split("=", 1)[1], 0)
        elif a.startswith("--max-s="):
            budget = float(a.split("=", 1)[1])
    if dl.elevation() != 1 and "--elevated" not in sys.argv[1:]:
        args = [sys.executable, os.path.abspath(__file__), "--elevated"]
        if dry:
            args.append("--dry=%d" % dry)
        if start is not None:
            args.append("--from=%#x" % start)
        if budget:
            args.append("--max-s=%g" % budget)
        params = subprocess.list2cmdline(args)
        try:
            os.remove(OUT)                    # so a stale OUT cannot fool us
        except OSError:
            pass
        print("parent: elevating %s" % params)
        msg = dl.run_elevated(params)
        print("parent: %s" % msg)
        if not os.path.exists(OUT):
            return wr(3, "ELEV_FAIL %s" % msg)
        print(open(OUT, encoding="utf-8").read().strip())
        return 0
    log("basehunt  %s  dry=%d" % (time.strftime("%Y-%m-%d %H:%M:%S"), dry))
    try:
        g = gio.Gio(chunk=dl.SCAN_CHUNK)
    except OSError as e:
        log("FATAL: %s" % e)
        return wr(2, "FATAL no transport")
    try:
        ranges, note = dl.usable_ranges(g.ram_top, None, None)
        log("RAMTOP %#x %s ranges=%d" % (g.ram_top, note, len(ranges)))
        b, resume, why = hunt(g, ranges, NODE_FL, g.ram_top, dry, start, budget)
        if b is None:
            if why == "budget":
                return wr(1, "HUNT_TIMEOUT resume_pa=%#x" % resume)
            if why == "dry":
                return wr(0, "DRY_OK stopped_after_shapes resume_pa=%#x" % resume)
            return wr(1, "NO_BASE")
        seen = set()
        fl = walk(g, b, NODE_FL, seen, "FL")
        bl = walk(g, b, NODE_BL, seen, "BL")
        log("FL %d hops, BL %d hops" % (len(fl), len(bl)))
        targets = [x for x in fl + bl if isinstance(x[0], int) and x[0] == 0x1570]
        log("pid 0x1570 hops: %d" % len(targets))
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
            why = dl.probe_dtb(g, dtb)
            log("   probe: %s" % why)
            if "pdpt ram" not in why:
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
            return wr(0, "DUMP_OK pid=0x1570 base=%#x dtb=%#x va=%#x sha256=%s"
                      % (base, dtb, mva, h))
        return wr(1, "NO_LIVE_OBJECT fl=%d bl=%d" % (len(fl), len(bl)))
    finally:
        g.close()


if __name__ == "__main__":
    sys.exit(main())

