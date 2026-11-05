"""p56_diff.py -- two-capture diff over captured entity slots.

Capture 1 is a p55_slots.txt whose SLOT lines carry pre= and post= hex around
the name.  This re-reads the same pages, re-finds the slots and prints only
the qword lanes whose bytes changed since capture 1 -- a health dword that
dropped or a coord float that drifted surfaces as a changed lane at a fixed
offset toward the name, no struct layout needed.
Read-only, elevated (gio open).

Usage: p56_diff.py --oldA=temp\\p55_slots.txt [--oldB=...]
                   --pages=0x626ea2000,0x739ae1000 --out=temp\\p56_diff.txt
"""
import os
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

ROOT = os.path.dirname(HERE)
PAGE = 0x1000
SLOTRE = re.compile(
    r"SLOT pa=(0x[0-9a-f]+) len=(0x[0-9a-f]+) (.*?)  pre=([0-9a-f]+) post=([0-9a-f]+)")
LOG = []
PRINT = bytes(range(0x20, 0x7F)) + b"\t\n\r"
TEXT_MAX = 0.5


def log(s):
    LOG.append(s)
    print(s)


def lane_tags(q):
    tags = []
    lo, hi = struct.unpack("<II", q)
    for d in (lo, hi):
        if 0 < d <= 1000:
            tags.append("h")
    for i in (0, 4):
        f = struct.unpack_from("<f", q, i)[0]
        if 0.5 <= abs(f) <= 20000.0 and f == f:
            tags.append("f")
    v = struct.unpack("<Q", q)[0]
    if v >> 48 == 0xFFFF:
        tags.append("k")
    elif 0x10000 <= v <= 0x7FFFFFFFFFFF:
        tags.append("u")
    if all(0x20 <= c < 0x7F for c in q if c) and any(q):
        tags.append("a")
    return "".join(sorted(set(tags)))


def wr(path, code, verdict):
    log("VERDICT: %s" % verdict)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(LOG) + "\n")
    return code


def parse_old(paths):
    out = []
    for p in paths:
        if not os.path.exists(p):
            log("old file missing: %s" % p)
            continue
        got = 0
        for line in open(p, encoding="utf-8", errors="replace"):
            m = SLOTRE.search(line)
            if not m:
                continue
            got += 1
            out.append((int(m.group(1), 16), int(m.group(2), 16), m.group(3),
                        bytes.fromhex(m.group(4)), bytes.fromhex(m.group(5))))
        log("old file %s: %d slot(s)" % (os.path.basename(p), got))
    return out


def ascii_ratio(b):
    if not b:
        return 1.0
    return sum(1 for x in b if x in PRINT) / len(b)


def locate(g, nb, hdr, pages, regions, fresh, CHUNK=0x10000):
    """Re-find needle nb whose 20-byte header (hash, name[4:8], len, NUL) intact.

    Returns (addr, buf, index) or None. Known pages first, then region sweeps;
    text-dominated pages are dropped because they forge needles.
    """
    def ok(buf, i):
        n = hdr["n"]
        if i < 0x14 or i + n >= len(buf):
            return False
        if buf[i - 4:i] != hdr["len4"]:            # u32 LE length, right before name
            return False
        if buf[i - 8:i - 4] != hdr["ch4"]:         # name[4:8] echo
            return False
        if buf[i - 0x0c:i - 8] != hdr["hash"]:     # name hash
            return False
        return buf[i + n:i + n + 1] == b"\0"

    for pg in pages:
        if pg not in fresh:
            try:
                fresh[pg] = bytes(g.read_phys_checked(pg, PAGE))
            except OSError as e:
                log("FAULT page=%#x %s" % (pg, e))
                fresh[pg] = None
        buf = fresh[pg]
        if buf is None or ascii_ratio(buf) > TEXT_MAX:
            continue
        i = buf.find(nb)
        while i >= 0:
            if ok(buf, i):
                return (pg | i, buf, i)
            i = buf.find(nb, i + 1)
    for lo, hi in regions:
        pa = hi - CHUNK
        while pa >= lo:
            try:
                blk = g.read_phys(pa, CHUNK)
            except OSError:
                pa -= CHUNK
                continue
            i = blk.find(nb)
            while i >= 0:
                poff = i & ~(PAGE - 1)
                if ok(blk, i) and ascii_ratio(blk[poff:poff + PAGE]) <= TEXT_MAX:
                    return (pa + i, blk, i)
                i = blk.find(nb, i + 1)
            pa -= CHUNK
    return None


def main(argv):
    olds, pages, regions, out = [], set(), [], os.path.join(ROOT, "temp", "p56_diff.txt")
    for a in argv:
        if a.startswith("--oldA="):
            olds.append(a[7:])
        elif a.startswith("--oldB="):
            olds.append(a[7:])
        elif a.startswith("--pages="):
            pages |= {int(x, 16) & ~(PAGE - 1) for x in a[8:].split(",")}
        elif a.startswith("--page="):
            pages.add(int(a[7:], 16) & ~(PAGE - 1))
        elif a.startswith("--sweep_lo="):
            regions.append([int(a[11:], 16), None])
        elif a.startswith("--sweep_hi="):
            if not regions or regions[-1][1] is not None:
                print("--sweep_hi needs a preceding --sweep_lo")
                return 2
            regions[-1][1] = int(a[11:], 16)
        elif a.startswith("--out="):
            out = a[6:]
    if not olds or not (pages or regions):
        print("usage: p56_diff.py --oldA=path [--oldB=path] "
              "--pages=0x..|--sweep_lo=0x.. --sweep_hi=0x.. --out=path")
        return 2
    log("# p56_diff %s olds=%d pages=%s regions=%s"
        % (time.strftime("%Y-%m-%d %H:%M:%S"), len(olds),
           " ".join(hex(p) for p in sorted(pages)),
           " ".join("%#x-%#x" % (lo, hi or 0) for lo, hi in regions)))
    olds = parse_old(olds)
    log("old slots: %d" % len(olds))
    if not olds:
        return wr(out, 4, "NO_OLD_SLOTS")
    try:
        g = gio.Gio()
    except OSError as e:
        log("FATAL: %s" % e)
        return wr(out, 3, "FATAL no transport")
    fresh = {}
    nsame = nchg = nmove = nmiss = nlanes = 0
    order_all = sorted(pages)
    for pa, n, name, pre, post in olds:
        nb = name[1:-1].encode("ascii", "replace")
        pg0 = pa & ~(PAGE - 1)
        hdr = {"n": n, "hash": pre[0x18:0x1c], "ch4": pre[0x1c:0x20],
               "len4": pre[0x20:0x24]}
        hit = locate(g, nb, hdr, [pg0] + [p for p in order_all if p != pg0],
                     regions, fresh)
        if hit is None:
            log("MISS %r (slot %#x, header no hit in window)" % (name, pa))
            nmiss += 1
            continue
        addr, buf, no = hit
        if addr != pa:
            log("MOVE %r %#x -> %#x" % (name, pa, addr))
            nmove += 1
        new_pre = buf[no - 0x30:no]
        new_post = buf[no + n:no + n + 0x40]
        hits_here = 0
        for tag, oldb, newb in (("pre", pre, new_pre), ("post", post, new_post)):
            m = min(len(oldb), len(newb))
            base = -0x30 if tag == "pre" else n
            for i in range(0, m - 7, 8):
                o, w = oldb[i:i + 8], newb[i:i + 8]
                if o == w:
                    continue
                hits_here += 1
                nlanes += 1
                log("  %s%+04x %r  tags %s/%s  old=%s new=%s"
                    % (tag[0], base + i, name, lane_tags(o),
                       lane_tags(w), o.hex(), w.hex()))
        if hits_here:
            log("CHG pa=%#x %s lanes=%d" % (addr, name, hits_here))
            nchg += 1
        else:
            nsame += 1
    g.close()
    log("")
    log("slots=%d changed=%d same=%d moved=%d missing=%d lanes=%d"
        % (len(olds), nchg, nsame, nmove, nmiss, nlanes))
    if not nlanes:
        return wr(out, 1, "NO_CHANGE")
    return wr(out, 0, "DIFF lanes=%d slots_changed=%d" % (nlanes, nchg))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
