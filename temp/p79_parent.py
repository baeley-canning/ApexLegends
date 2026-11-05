r"""p79_parent.py -- find the table that points AT a frame, and score its shape.

Forward walking needs the process PML4, which is the one page that will not
read.  But a PT does not need its parent to be readable to be usable: the
parent PD contains a present, PS-clear entry whose PFN is the PT frame, and
that entry is enough to know the PT's index, hence the VA range.  Searching
upwards is therefore real reconstruction, not a workaround.

Two details that make the scan honest:
  * a 64 KiB chunk read dies on a single blind page and takes 15 good pages
    with it, so a failed chunk is re-read page by page (chunk . BADPAGES
    instead of chunk . 16);
  * a 4 KiB leaf PTE pointing at the frame is indistinguishable from a
    PD -> PT pointer by value, so hits are classified by page shape instead
    of trusted: entries with PS set (2 MiB leaves) make it a PD, all-leaves
    makes it a PT that happens to map the frame as data.

Usage: p79_parent.py --pa=<frame> [--want=pd|pdpt] [--lo=..] [--hi=..]
Read-only.  Every hit is re-read as an exact qword before it is listed.
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio  # noqa: E402
import dumplive as dl  # noqa: E402

CHUNK = 0x10000
PAGE = 0x1000
CAP = 400
BF_FACTOR = 6

PA = 0
LO = HI = None
OUT = ""


def main():
    global PA, LO, HI, OUT
    for a in sys.argv[1:]:
        if a.startswith("--pa="):
            PA = int(a[5:], 0)
        elif a.startswith("--lo="):
            LO = int(a[5:], 0)
        elif a.startswith("--hi="):
            HI = int(a[5:], 0)
    if not PA:
        print("need --pa")
        return 2
    OUT = os.path.join(HERE, "_p79_parent_%x.txt" % PA)
    lines = []
    faults = rescued = 0

    def note(s):
        with open(OUT, "a", encoding="utf-8") as f:
            f.write("%s %s\n" % (time.strftime("%H:%M:%S"), s))

    try:
        os.remove(OUT)
    except OSError:
        pass
    note("start pa=%#x" % PA)
    pat = struct.pack("<Q", PA)[2:6]
    raw = []
    t0 = time.time()
    g = gio.Gio(chunk=CHUNK)
    try:
        ranges, note2 = dl.usable_ranges(g.ram_top, LO or None, HI or None)
        lines.append("ranges=%d %s" % (len(ranges), note2))
        note("ranges=%d" % len(ranges))

        def hunt(blk, base):
            if len(raw) >= CAP:
                return
            p = blk.find(pat)
            while p >= 0:
                if (base + p) & 7 == 2:
                    raw.append(base + p - 2)
                if len(raw) >= CAP:
                    return
                p = blk.find(pat, p + 1)

        for lo, hi in ranges:
            cur = lo
            while cur < hi:
                n = min(CHUNK, hi - cur)
                try:
                    hunt(g.read_phys(cur, n), cur)
                    cur += n
                    continue
                except OSError:
                    pass
                faults += 1
                sub = cur
                while sub < cur + n:
                    try:
                        hunt(g.read_phys(sub, PAGE), sub)
                        rescued += 1
                    except OSError:
                        pass
                    sub += PAGE
                cur += n
    finally:
        g.close()
    lines.append("raw=%d faults=%d rescued_pages=%d %.1fs"
                 % (len(raw), faults, rescued, time.time() - t0))
    note("raw=%d" % len(raw))

    g = gio.Gio()
    hits = []
    try:
        for entry_pa in raw:
            page = entry_pa & ~0xFFF
            idx = (entry_pa & 0xFFF) // 8
            if not g.is_ram(page):
                continue
            try:
                q = g.u64(entry_pa)
                if (q & 0x000FFFFFFFFFF000) != PA or not q & 1 or q & 0x80:
                    continue
                blk = g.read_phys(page, PAGE)
            except OSError:
                continue
            ents = struct.unpack_from("<512Q", blk)
            pres = [i for i, v in enumerate(ents) if v & 1]
            ps = sum(1 for i in pres if ents[i] & 0x80)
            tbl = len(pres) - ps
            al2m = sum(1 for i in pres if not ents[i] & 0x1FFFFF)
            score = ps * 8 + min(tbl, 60) + (40 if idx % 8 == 0 else 0)
            hits.append((score, page, idx, q, len(pres), ps, al2m))
            note("hit %#x idx=%d" % (page, idx))
    finally:
        g.close()

    hits.sort(reverse=True)
    lines.append("hits=%d" % len(hits))
    for score, page, idx, q, npres, ps, al2m in hits[:40]:
        kind = "PD->PT" if ps else "PT/leaf page"
        lines.append("SHAPE %#x idx=%d q=%#x present=%d ps=%d 2MiBal=%d "
                     "score=%d kind=%s" % (page, idx, q, npres, ps, al2m,
                                           score, kind))
    top = hits[0] if hits else None
    if not top:
        lines.append("VERDICT: no parent pointer to %#x" % PA)
    elif top[5]:
        lines.append("VERDICT: best parent %#x idx=%d is PD-shaped (ps=%d)"
                     % (top[1], top[2], top[5]))
    else:
        lines.append("VERDICT: only leaf-table hits -- %#x is mapped as data, "
                     "parent PD missing" % PA)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
