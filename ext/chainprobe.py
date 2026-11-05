"""chainprobe.py -- find the live ActiveProcessLinks chain without a working CR3.

The three decoy blocks carry a LIST_ENTRY at +0x1d8 whose two pointers both end
in 0x258, so the neighbours' entry sits at +0x258 and their base at page offset
0x258-0x1d8 = 0x080.  That is a physical fingerprint independent of any page
table:

  1. scan RAM for a page with type 3 at +0x080, a plausible pid at +0x250 and a
     KVA pair on lanes 0x258/0x260 -- the neighbour EPROCESS itself;
  2. calibrate the kernel's linear VA base B from that page's own flink:
     B = flink_va - (page_pa + 0x258);
  3. walk the list from the decoy in both directions, VA -> PA = va - B, and
     stop at a pid 0x1570 hop whose DirectoryTableBase page actually reads;
  4. walk that address space and dump the image.

Everything is read-only; chunk faults are rescued at 4 KiB.
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
OUT = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_OUT", "p44e_chain.txt"))
PROG = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_PROG", "p44e_progress.txt"))
DECOY = [0x2481D60C0, 0x62BC6E190, 0x7DE10FBF0]
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


def page_ok(p):
    """Neighbour fingerprint: EPROCESS base at 0x080 of the page."""
    if p[0x080] != 3:
        return False
    pid = struct.unpack_from("<I", p, 0x250)[0]
    if not (0 < pid <= 0x100000):
        return False
    fl = struct.unpack_from("<Q", p, 0x258)[0]
    bl = struct.unpack_from("<Q", p, 0x260)[0]
    if fl >> 48 != 0xFFFF or bl >> 48 != 0xFFFF:
        return False
    if (fl & 0xFFF) != 0x258 or (bl & 0xFFF) != 0x260:
        return False
    nm = p[0x080 + 0x338:0x080 + 0x338 + 15]
    return all(0x20 <= c < 0x7F for c in nm) and nm != b"\x00" * len(nm)


def scan(g, ranges):
    hits = []
    bad = 0
    for rlo, rhi in ranges:
        pa = rlo
        while pa < rhi:
            n = min(dl.SCAN_CHUNK, rhi - pa)
            try:
                blk = g.read_phys(pa, n)
            except OSError:
                for sub in range(0, n, 0x1000):
                    try:
                        b1 = g.read_phys(pa + sub, 0x1000)
                    except OSError:
                        bad += 1
                        continue
                    if b1[0x80] == 3 and page_ok(b1):
                        hits.append(pa + sub)
                prog("FAULT pa=%#x hits=%d" % (pa, len(hits)))
                pa += n
                continue
            for off in range(0, n, 0x1000):
                if blk[off + 0x80] == 3 and page_ok(blk[off:off + 0x1000]):
                    hits.append(pa + off)
                    prog("HIT page=%#x" % (pa + off))
            pa += n
    prog("SCANEND bad4k=%d hits=%d" % (bad, len(hits)))
    return hits


def wr(code, verdict):
    log("VERDICT: %s" % verdict)
    open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
    return code


def main():
    log("chainprobe  %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
    try:
        g = gio.Gio(chunk=dl.SCAN_CHUNK)
    except OSError as e:
        log("FATAL: %s" % e)
        return wr(1, "FATAL no transport")
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    log("RAMMAP %s ranges=%d" % (note, len(ranges)))
    t0 = time.perf_counter()
    pages = scan(g, ranges)
    log("fingerprint pages: %d  %.1fs" % (len(pages), time.perf_counter() - t0))
    for pa in pages[:12]:
        try:
            p = g.read_phys(pa, 0x1000)
        except OSError:
            continue
        log("  page=%#x pid=%#x name=%r fl=%016x bl=%016x"
            % (pa, struct.unpack_from("<I", p, 0x250)[0], p[0x3B8:0x3B8 + 15],
               struct.unpack_from("<Q", p, 0x258)[0],
               struct.unpack_from("<Q", p, 0x260)[0]))
    if not pages:
        g.close()
        return wr(3, "NO_FINGERPRINT")

    base = None
    for pa in pages:
        try:
            p = g.read_phys(pa, 0x1000)
        except OSError:
            continue
        fl = struct.unpack_from("<Q", p, 0x258)[0]
        cand = fl - (pa + 0x258)
        if cand & 0xFFF:
            continue
        if 0xFFFFA40000000000 <= cand <= 0xFFFFA40200000000:
            base = cand
            log("calibrated B=%#x from page=%#x flink=%#x" % (base, pa, fl))
            break
    if base is None:
        g.close()
        return wr(4, "NO_CALIBRATION")

    best = None
    seen = set()
    for start in DECOY:
        try:
            p = g.read_phys(start & ~0xFFF, 0x1000)
        except OSError:
            continue
        for lane in (0x1D8, 0x1E0):
            va = struct.unpack_from("<Q", p, (start & 0xFFF) + lane)[0]
            for hop in range(HOP_CAP):
                if (va >> 48) != 0xFFFF or not g.is_ram(va):
                    break
                bp = va - 0x1D8
                if bp in seen or not g.is_ram(bp):
                    break
                seen.add(bp)
                try:
                    q = g.read_phys(bp & ~0xFFF, 0x2000)
                except OSError:
                    log("  hop %3d va=%#x base=%#x fault" % (hop, va, bp))
                    break
                b = bp & 0xFFF
                pid = struct.unpack_from("<I", q, b + 0x1D0)[0]
                nm = q[b + 0x338:b + 0x338 + 15]
                dtb = struct.unpack_from("<Q", q, b + 0x28)[0]
                live = False
                if dtb:
                    try:
                        g.read_phys(dtb & dl.MASK, 0x10)
                        live = True
                    except OSError:
                        pass
                log("  hop %3d pid=%#6x live=%-5s name=%r dtb=%#x"
                    % (hop, pid, live, nm, dtb))
                if pid == 0x1570 and live and best is None:
                    best = (bp, dtb)
                    log("  FOUND live object at %#x dtb=%#x" % (bp, dtb))
                va = struct.unpack_from("<Q", q, b + lane)[0]
    if not best:
        g.close()
        return wr(5, "NO_LIVE_OBJECT")

    bp, dtb = best
    try:
        r = dl.find_mz(g, dtb)
    except OSError as e:
        log("walk fault %s" % e)
        g.close()
        return wr(6, "WALK_FAULT")
    log("find_mz -> %s" % (("va=%#x size=%#x secs=%d"
                            % (r[0], r[1]["size"], len(r[1]["secs"])))
                           if r else "no PE"))
    if not r:
        log("why: %s" % dl.probe_dtb(g, dtb))
        g.close()
        return wr(7, "NO_MZ")
    base_va, meta = r
    try:
        st = dl.Stats()
        buf = bytearray(meta["size"])
        w = dl.Walk(g, dtb)
        dl.dump_range(g, w, buf, base_va, 0, meta["hdr"], st)
        for name, va, vsize in meta["secs"]:
            dl.dump_range(g, w, buf, base_va, va, vsize, st)
    except OSError as e:
        g.close()
        return wr(8, "DUMP_FAULT %s" % e)
    out_bin = os.path.join(ROOT, "temp", "r5apex_chain_%s.bin"
                           % time.strftime("%Y%m%d_%H%M%S"))
    with open(out_bin, "wb") as f:
        f.write(buf)
    log("DUMP %s size=%#x fail=%d" % (out_bin, len(buf), st.fail))
    g.close()
    if st.read < 0x4000000 or st.fail:
        return wr(9, "DUMP_PARTIAL read=%d fail=%d" % (st.read, st.fail))
    return wr(0, "DUMP_OK %s" % out_bin)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        import traceback
        log("CRASH %s: %s" % (type(e).__name__, e))
        log(traceback.format_exc().replace("\n", " | ")[:900])
        sys.exit(wr(10, "CRASH"))
