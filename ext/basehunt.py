"""basehunt.py -- brute-force the kernel linear-map base B for the decoy flink.

paperobe3/4 showed the decoys carry a LIST_ENTRY pair at +0x1d8 whose two values
are system-region VAs on lane 0x258.  chainprobe's physical fingerprint at page
offset 0x080 found nothing, so the neighbours are not on that page phase; the
only assumption left is a linear map  PA = VA - B  with B random per boot.

B is constrained: PA must stay below RAM top, so B lies in (VA - ram_top, VA).
Every page-aligned B in that window is tried; a candidate is accepted only when
all of these hold on the mapped page:

  * byte +0x080 == 3, pid +0x250 in range, printable ImageFileName +0x3b8,
  * a KVA pair on lanes 0x258/0x260,
  * reciprocal proof: the decoy's own VA under the same B must still read as a
    live EPROCESS whose +0x1d8/+0x1e0 equal the two pointers.

Accepted B -> walk the list both ways for a live pid 0x1570 and dump the image.
READ-ONLY.
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
LINK = 0x2481D60C0
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
    """Neighbour EPROCESS at +0x080 of the page -> (pid, fl, bl) or None."""
    if p[0x80] != 3:
        return None
    pid = struct.unpack_from("<I", p, 0x250)[0]
    if not (0 < pid <= 0x100000):
        return None
    fl, bl = struct.unpack_from("<QQ", p, 0x258)
    if fl >> 48 != 0xFFFF or bl >> 48 != 0xFFFF:
        return None
    if (fl & 0xFFF) != 0x258 or (bl & 0xFFF) != 0x260:
        return None
    nm = p[0x3B8:0x3B8 + 15]
    if nm == b"\x00" * 15 or not all(0x20 <= c < 0x7F for c in nm):
        return None
    return pid, fl, bl


def wr(code, verdict):
    log("VERDICT: %s" % verdict)
    open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
    return code


def decoy_read(g, b, pa):
    """Read the decoy through candidate B and verify reciprocity."""
    va = b + pa
    try:
        page = g.read_phys(va & ~0xFFF, 0x1000)
    except OSError:
        return None
    o = va & 0xFFF
    if page[o] != 3:
        return None
    pid = struct.unpack_from("<I", page, o + 0x1D0)[0]
    nm = page[o + 0x338:o + 0x338 + 15]
    if pid != 0x1570 or not nm.startswith(b"r5apex"):
        return None
    return struct.unpack_from("<QQ", page, o + 0x1D8)


def hunt(g, va, ram_top):
    page = va & ~0xFFF
    lo = page - ram_top
    if lo < 0xFFFFA40000000000:
        lo = 0xFFFFA40000000000
    lo = (lo + 0xFFF) & ~0xFFF
    n = (page - lo) // 0x1000
    log("window B=%#x..%#x  %d candidates" % (lo, page, n))
    t0 = time.perf_counter()
    tried = 0
    for b in range(lo, page, 0x1000):
        pa = page - b
        if not g.is_ram(pa):
            continue
        try:
            p = g.read_phys(pa, 0x1000)
        except OSError:
            continue
        tried += 1
        s = shape(p)
        if not s:
            continue
        pid, fl, bl = s
        log("shape B=%#x pa=%#x pid=%#x name=%r" % (b, pa, pid, p[0x3B8:0x3C7]))
        r = decoy_read(g, b, LINK)
        if not r:
            log("  reciprocity failed")
            continue
        log("  ACCEPT B=%#x decoy flink=%#x blink=%#x" % (b, r[0], r[1]))
        if r[0] != va:
            log("  WARN decoy flink %#x != %#x" % (r[0], va))
        prog("ACCEPT b=%#x" % b)
        log("  tried=%d %.1fs" % (tried, time.perf_counter() - t0))
        return b
    log("no candidate  tried=%d %.1fs" % (tried, time.perf_counter() - t0))


def hop(g, b, va, seen):
    """VA -> (pid, base_pa, fl, bl, name) for a list node, or None."""
    pa = va - b
    base = (pa - 0x1D8) & ~0x0F
    if base in seen or not g.is_ram(base) or (base & 0xFFF) > 0xFF0:
        return None
    seen.add(base)
    try:
        p = g.read_phys(base, 0x1000)
    except OSError:
        return None
    if p[0] != 3:
        return None
    pid = struct.unpack_from("<I", p, 0x1D0)[0]
    fl, bl = struct.unpack_from("<QQ", p, 0x1D8)
    return pid, base, fl, bl, p[0x338:0x347]


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
    if not dl.elevation():
        return wr(3, "NOT_ELEVATED")
    log("basehunt  %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
    try:
        g = gio.Gio(chunk=dl.SCAN_CHUNK)
    except OSError as e:
        log("FATAL: %s" % e)
        return wr(2, "FATAL no transport")
    try:
        ranges, note = dl.usable_ranges(g.ram_top, None, None)
        log("RAMTOP %#x %s ranges=%d" % (g.ram_top, note, len(ranges)))
        b = hunt(g, 0xFFFFA401B25A5258, g.ram_top)
        if b is None:
            return wr(1, "NO_BASE")
        seen = set()
        fl = walk(g, b, 0xFFFFA401B25A5258, seen, "FL")
        bl = walk(g, b, 0xFFFFA401B7EA0258, seen, "BL")
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

