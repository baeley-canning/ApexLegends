"""go21_elect.py -- motion-free VP election: Nessies vote, matrices compete.
1. collect Nessie name-hit positions (producer semantics, pos at name-pdelta)
2. loosen the candidate net over the .data tail (+ go21_pick seed table)
3. each candidate votes: in-frame inlier count via qk_phys.project
--write=1 caches temp\qk_offsets.txt for the producer."""
import math, os, struct, sys, time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "ext"))

import gio
import dumplive as dl
import qk_phys as PM

IMAGE_PA = 0x048C6BD000
SEEDS = (0x0DE43604, 0x0DE43270, 0x0DE431E0, 0x0DE43080,
         0x0DDF5A34, 0x0DDB5C04, 0x0DDB5844, 0x0DDB5390)
DATA_VA = 0x0334C000
DATA_SIZE = 0xAB23AAC
TAIL = 0x400000
W, H = 1920, 1080


def arg(name, default=None, cast=str):
    for i, a in enumerate(sys.argv):
        if a == "--" + name and i + 1 < len(sys.argv):
            return cast(sys.argv[i + 1])
        if a.startswith("--" + name + "="):
            return cast(a.split("=", 1)[1])
    return default


def collect_ents(g, ranges, needle, pdelta):
    pats = [needle.encode("utf-16-le"), needle.encode("ascii")]
    hits = []
    for rlo, rhi in ranges:
        pa = (rlo + 7) & ~7
        while pa + 0x10000 <= rhi:
            try:
                blk = dl.retry_phys(g, pa, 0x10000, tries=1)
            except OSError:
                pa += 0x10000
                continue
            for pat in pats:
                i = blk.find(pat)
                while i >= 0:
                    hits.append(pa + i)
                    i = blk.find(pat, i + 1)
            pa += 0x10000
    ents = set()
    for a in hits:
        try:
            x, y, z = struct.unpack("<fff", dl.retry_phys(g, a - pdelta, 12, tries=1))
        except OSError:
            continue
        if all(abs(c) < 20000.0 and c == c for c in (x, y, z)):
            ents.add((int(x), int(y), int(z)))
    return hits, sorted(ents)


def broaden(g):
    out = {}
    end = DATA_VA + DATA_SIZE
    cur = end - TAIL
    while cur + 0x10000 <= end:
        try:
            blk = dl.retry_phys(g, IMAGE_PA + cur, 0x10000, tries=1)
        except OSError:
            cur += 0x10000
            continue
        for i in range(0, len(blk) - 64, 4):
            m = struct.unpack_from("<16f", blk, i)
            if m[15] != m[15] or m[11] != m[11]:
                continue
            if not (abs(abs(m[15]) - 1.0) < 0.01 or abs(abs(m[11]) - 1.0) < 0.01):
                continue
            if all(x == x and abs(x) < 1e10 for x in m):
                out[cur + i] = m
        cur += 0x10000
    return out


def vote(ents, m):
    n = 0
    for (x, y, z) in ents:
        p = PM.project(m, float(x), float(y), float(z), W, H)
        if p and 0 <= p[0] <= W and 0 <= p[1] <= H and 30.0 <= p[2] <= 15000.0:
            n += 1
    return n

def main():
    if not dl.elevation() and "--no-elevate" not in sys.argv:
        argv = [os.path.abspath(a) for a in sys.argv]
        cmd = " ".join('"%s"' % a if " " in a else a for a in argv) + " --no-elevate"
        print(dl.run_elevated(cmd))
        return 0
    needle = arg("mate", "Nessie")
    pdelta = arg("pdelta", 0xEEC, lambda s: int(s, 0))
    write = arg("write", 0, lambda s: int(s, 0))
    pick = arg("pick", None, lambda s: int(s, 0))

    g = gio.Gio(chunk=0x10000)
    try:
        ranges, _ = dl.usable_ranges(g.ram_top, None, None)
        t0 = time.time()
        hits, ents = collect_ents(g, ranges, needle, pdelta)
        print("RESULT: needle=%r hits=%d ents=%d (%.1fs) pdelta=%#x"
              % (needle, len(hits), len(ents), time.time() - t0, pdelta))
        if not ents:
            print("VERDICT: NO-ENTS - pos plausibility dead, try --pdelta=f58")
            return 3
        rows = dict((r, None) for r in SEEDS)
        extra = broaden(g)
        for r in extra:
            rows.setdefault(r, extra[r])
        print("RESULT: seeds=%d loosened=%d total=%d"
              % (len(SEEDS), len(extra), len(rows)))
        scored = []
        for rva in sorted(rows):
            m = rows[rva]
            if m is None:
                try:
                    m = struct.unpack("<16f", dl.retry_phys(g, IMAGE_PA + rva, 64, tries=2))
                except OSError:
                    continue
            n = vote(ents, m)
            scored.append((n, rva))
        scored.sort(key=lambda t: (-t[0], t[1]))
        for n, rva in scored[:12]:
            print("ELECT: rva=%#010x inliers=%d/%d" % (rva, n, len(ents)))
        if not scored:
            print("VERDICT: EMPTY-NET")
            return 4
        if write or pick is not None:
            idx = pick if pick is not None else 0
            if idx >= len(scored):
                print("VERDICT: BAD-PICK")
                return 5
            n, rva = scored[idx]
            with open(os.path.join(HERE, "temp", "qk_offsets.txt"), "w") as f:
                f.write("image_pa=0x%X\nvp_rva=0x%X\n" % (IMAGE_PA, rva))
            print("RESULT: cached image_pa=%#x vp_rva=%#x inliers=%d/%d"
                  % (IMAGE_PA, rva, n, len(ents)))
            print("VERDICT: %s" % ("PICKED" if n >= 3 else "PICKED-WEAK"))
        else:
            print("RESULT: best rva=%#010x inliers=%d/%d"
                  % (scored[0][1], scored[0][0], len(ents)))
            print("VERDICT: %s" % ("FRONT-RUNNER" if scored[0][0] >= 3 else "NO-QUORUM"))
        return 0
    finally:
        g.close()


if __name__ == "__main__":
    main()
