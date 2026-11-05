r"""p80_rank.py -- tell a real PD from a stale one among p79's candidates.

p79 found 89 pages holding a PS-clear pointer to the frame.  A live PT is
pointed at by exactly one live PD, so 88 of them are stale (freed page tables
whose contents survive until reuse) or something else entirely.  Ranking by
density alone does not separate them: a freed PD keeps its density.

The physical invariant does separate them.  A PD's bit-7 entries are 2 MiB
leaves, and a 2 MiB leaf must name a 2 MiB aligned frame -- bits 12..20 of the
entry are PFN bits and are zero.  A PT that merely has PAT (also bit 7) set on
its entries has unaligned targets.  p79 tested `q & 0x1FFFFF`, which includes
the flag bits, so every candidate scored zero; this re-reads each candidate
and computes it on the PFN field.

Second signal: does the entry's target frame actually read, and do the PD's
other PS-clear children look like tables?  A stale PD points at frames that
have been recycled.

Usage: p80_rank.py _p79_parent_<pa>.txt
Read-only.
"""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio  # noqa: E402

PAGE = 0x1000
OUT = os.path.join(HERE, "_p80_rank.txt")
RX = re.compile(r"^SHAPE (0x[0-9a-f]+) idx=(\d+)")


def main():
    if len(sys.argv) < 2:
        print("need a p79 output file")
        return 2
    cands = []
    with open(sys.argv[1], encoding="utf-8") as f:
        for ln in f:
            m = RX.match(ln)
            if m:
                cands.append((int(m.group(1), 16), int(m.group(2))))
    if not cands:
        print("no SHAPE lines")
        return 2
    lines = ["candidates=%d" % len(cands)]

    def log(s):
        lines.append(s)

    g = gio.Gio()
    rows = []
    try:
        for page, idx in cands:
            try:
                blk = g.read_phys(page, PAGE)
            except OSError as e:
                log("%#x DEAD %d" % (page, e.args[0] if e.args else -1))
                continue
            ents = struct.unpack_from("<512Q", blk)
            pres = [i for i, v in enumerate(ents) if v & 1]
            ps = [i for i in pres if ents[i] & 0x80]
            ps_al = [i for i in ps if not ents[i] & 0x1FF000]
            ps_ram = [i for i in ps_al if g.is_ram((ents[i] >> 12) << 12)]
            ps_uniq_hi = len(set((ents[i] >> 12) << 12 for i in ps_al))
            frac = (100 * len(ps_al) // len(ps)) if ps else 0
            rows.append((frac, len(ps_al), len(ps_ram), ps_uniq_hi, page, idx,
                         len(pres), len(ps)))
    finally:
        g.close()
    rows.sort(reverse=True)
    for frac, nal, nram, nuniq, page, idx, npres, nps in rows:
        log("%#x idx=%d present=%d ps=%d ps_aligned=%d (%d%%) ps_al_ram=%d "
            "ps_al_uniq=%d" % (page, idx, npres, nps, nal, frac, nram, nuniq))
    best = rows[0] if rows else None
    if not best:
        log("VERDICT: none readable")
    elif best[0] >= 90 and best[1] >= 8:
        log("VERDICT: best %#x idx=%d has %d aligned 2 MiB leaves, %d of them "
            "RAM -- reads as a live PD" % (best[4], best[5], best[1], best[2]))
    else:
        log("VERDICT: no candidate is PS-aligned enough (%d%% at best) -- the "
            "hit pages are PTs with PAT or stale" % (best[0] or 0))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
