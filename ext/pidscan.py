"""pidscan.py -- find _EPROCESS by UniqueProcessId instead of by name.

Every name-anchored attempt assumes EPROCESS.ImageFileName holds the image name.
p43v covered the whole map, found 5373 name copies and only 8 pid-shaped
neighbours, all inside user-mode records -- not one object with a dispatcher
type, a frame at +0x28 and a kernel LIST_ENTRY.  So the anchor is inverted:
scan for the pid dword, then keep only addresses whose surroundings *are* an
object (type byte, DTB frame, KVA links), and read back whatever name sits at
base+0x338.  If the name turns out to differ, the name gate was the bug; if an
object appears, the layout is right and the pid offset gets confirmed.

Read-only: gdrv3 open only, same safe class as p40-p43v.  Chunk faults are
retried at 4 KiB.  Every survivor is reported with its pid offset, and the few
best ones are probed with find_mz (which only reads tables and pages).
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
OUT = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_OUT", "p43w_pidscan.txt"))
PROG = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_PROG", "p43w_progress.txt"))
PID = 0x1570
# The point of the probe is that the pid offset is *unknown*: all five 8-aligned
# lanes around 0x1d0 are tried and the one that passes is logged with the hit.
PID_OFFS = (0x1C0, 0x1C8, 0x1D0, 0x1D8, 0x1E0)
RAW_CAP = 40000
KEEP = 400

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


def scan(g, ranges):
    """Every 4-byte-aligned pid dword, faults rescued at 4 KiB."""
    pat = struct.pack("<I", PID)
    hits = []
    bad = rescued = chunks = 0
    scanned = 0
    nxt = dl.CKPT_BYTES
    t0 = time.perf_counter()

    def take(blk, base):
        off = 0
        while len(hits) < RAW_CAP:
            i = blk.find(pat, off)
            if i < 0:
                return
            if ((base + i) & 3) == 0:
                hits.append((base + i, blk, i))
            off = i + 1

    for rlo, rhi in ranges:
        pa = rlo
        while pa < rhi and len(hits) < RAW_CAP:
            n = min(dl.SCAN_CHUNK, rhi - pa)
            try:
                blk = g.read_phys(pa, n)
            except OSError:
                chunks += 1
                for sub in range(0, n, 0x1000):
                    sn = min(0x1000, n - sub)
                    try:
                        sblk = g.read_phys(pa + sub, sn)
                    except OSError:
                        bad += 1
                        continue
                    rescued += 1
                    take(sblk, pa + sub)
                prog("FAULT pa=%#x bad4k=%d" % (pa, bad))
                pa += n
            else:
                chunks += 1
                take(blk, pa)
                pa += n
            scanned += n
            if scanned >= nxt:
                prog("CKPT pa=%#x scanned=%d MiB hits=%d bad=%d rescued=%d %.1fs"
                     % (pa, scanned >> 20, len(hits), bad, rescued,
                        time.perf_counter() - t0))
                nxt += dl.CKPT_BYTES
    prog("SCANEND scanned=%d MiB chunks=%d hits=%d bad4k=%d rescued=%d %.1fs"
         % (scanned >> 20, chunks, len(hits), bad, rescued,
            time.perf_counter() - t0))
    return hits



def shape(g, blk, i):
    """Object tests around one pid dword; yields (off, b, dtb, score, why)."""
    for off in PID_OFFS:
        b = i - off
        if b < 0 or b + 0x350 > len(blk):
            continue
        otype = blk[b]
        dtb = struct.unpack_from("<Q", blk, b + 0x28)[0]
        if not (otype <= 6 and dl.valid_cr3(g, dtb)):
            continue
        score = 0
        why = []
        if otype == 3:
            score += 4                       # ProcessObject
        else:
            why.append("type=%d" % otype)
        if struct.unpack_from("<Q", blk, b + 0x258)[0] >> 48 == 0xFFFF:
            score += 4                       # flink is a kernel pointer
        pc = blk[b + 0x347]
        score += 4 if pc == 2 else 0
        if struct.unpack_from("<Q", blk, b + 0x248)[0] >> 48 == 0xFFFF:
            score += 2                       # token
        peb = struct.unpack_from("<Q", blk, b + 0x2E0)[0]
        if 0 < peb < 0x800000000000 and not (peb & 7):
            score += 2
        if off == 0x1D0:
            score += 4
        yield off, b, dtb, score, why


def main():
    pid = None
    for a in sys.argv:
        if a.startswith("--pid="):
            pid = int(a.split("=", 1)[1])
    PID2 = pid or PID
    log("pidscan  %s  pid=%#x" % (time.strftime("%Y-%m-%d %H:%M:%S"), PID2))
    log("pure-read probe: device open only; pid anchor, name read back")
    try:
        g = gio.Gio(chunk=dl.SCAN_CHUNK)
    except OSError as e:
        log("FATAL: %s" % e)
        return wr(1, "FATAL no transport")
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    log("RAMMAP %s ranges=%d total=%d MiB" % (note, len(ranges),
                                              sum(b - a for a, b in ranges) >> 20))
    for a, b in ranges:
        prog("RANGE %#x-%#x" % (a, b))
    if not ranges:
        g.close()
        return wr(2, "NO_RANGES")
    t0 = time.perf_counter()
    hits = scan(g, ranges)
    log("scan: %d raw pid hits, %.1f s" % (len(hits), time.perf_counter() - t0))

    cands = []
    seen = set()
    for addr, blk, i in hits:
        for off, b, dtb, score, why in shape(g, blk, i):
            base = (addr - i) + b
            if base in seen:
                continue
            seen.add(base)
            log("  shape base=%#x pid@%#x dtb=%#x score=%d %s"
                % (base, off, dtb, score, " ".join(why)))
            cands.append((score, base, off, dtb))
    log("shaped candidates: %d of %d hits" % (len(cands), len(hits)))
    cands.sort(key=lambda c: -c[0])

    # read back the name each survivor claims is at +0x338, plus its neighbours
    final = []
    for score, base, off, dtb in cands[:KEEP]:
        try:
            p = g.read_phys(base & ~0xFFF, 0x2000)
        except OSError:
            log("  base=%#x window faulted" % base)
            continue
        b = base & 0xFFF
        nm = p[b + 0x338:b + 0x338 + 16]
        txt = nm.rstrip(b"\x00").decode("latin-1")
        hit_name = nm[:15] == dl.NAME
        fl = struct.unpack_from("<Q", p, b + 0x258)[0]
        tok = struct.unpack_from("<Q", p, b + 0x248)[0]
        peb = struct.unpack_from("<Q", p, b + 0x2E0)[0]
        log("  base=%#x pid@%#x pc=%#x name=%r hit_name=%s flink=%016x "
            "token=%016x peb=%016x score=%d"
            % (base, off, p[b + 0x347], txt, hit_name, fl, tok, peb, score))
        final.append((score + (20 if hit_name else 0), base, off, dtb, txt))

    final.sort(key=lambda c: -c[0])
    log("top:")
    for score, base, off, dtb, txt in final[:8]:
        log("  %6d base=%#x pid@%#x dtb=%#x name=%r" % (score, base, off, dtb, txt))
    walked = 0
    for score, base, off, dtb, txt in final[:3]:
        try:
            r = dl.find_mz(g, dtb)
        except OSError as e:
            log("  walk base=%#x dtb=%#x fault %s" % (base, dtb, e))
            continue
        log("  walk base=%#x dtb=%#x -> %s"
            % (base, dtb, ("image va=%#x size=%#x" % (r[0], r[1]["size"]))
               if r else "no PE"))
        if r:
            walked += 1
    g.close()
    if not hits:
        return wr(2, "NO_PID_HITS")
    if not cands:
        return wr(3, "NO_SHAPE")
    if not walked:
        return wr(4, "NO_MZ")
    return wr(0, "PE_FOUND")


def wr(code, verdict):
    log("VERDICT: %s" % verdict)
    open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
    return code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:                     # OUT must exist even on a crash
        import traceback
        log("CRASH %s: %s" % (type(e).__name__, e))
        log(traceback.format_exc().replace("\n", " | ")[:900])
        sys.exit(wr(9, "CRASH %s" % type(e).__name__))
