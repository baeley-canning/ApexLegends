r"""p78_dump_frame.py -- dump 0x6c6af0000 while it is readable, then classify it.

p77: the dead frame answers OK right now and its entries are PTE-shaped
(0x143ed88e1, PFNs near 0x143ed8).  It is claimed to be a PML4, but 94 present
entries in the low half and 110 in the high half are far too many for a PML4
(a process needs a handful), and a PML4 leaf bit only exists on 5-level
machines.  So the page is dumped first (a readable frame can go blind again at
any moment) and then classified instead of assumed:

  * present count per 64-entry band
  * of the present entries, how many are 2 MiB aligned   -> PD if most are
  * of the present entries, how many are 4 KiB aligned
  * the first 8, and the entries at indexes 0/1/255/256/511
  * a bit tally for bits 5,6,7,8,9,10,11,12 over present entries

A PD's children are PTs or 2 MiB leaves; a PML4's entry 255 must be present
and point at a PDPT.  The verdict string names the level the numbers support.
Read-only on the device; the dump goes to temp\p78_6c6af.bin.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio  # noqa: E402

OUT = os.path.join(HERE, "_p78_dump_frame.txt")
BIN = os.path.join(HERE, "p78_6c6af.bin")
PAGE = 0x1000
TARGET = 0x6C6AF0000
NEIGH = (TARGET - PAGE, TARGET + PAGE)


def log(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")
    print(s)


def main():
    for p in (OUT, BIN):
        if os.path.exists(p):
            os.remove(p)
    log("p78 dump frame %#x" % TARGET)
    with gio.Gio() as g:
        page = None
        for i in range(5):
            try:
                page = g.read_phys(TARGET, PAGE)
                log("target read OK on try %d" % (i + 1))
                break
            except OSError as e:
                log("target read try %d err %d" % (i + 1, e.args[0] if e.args else -1))
        if page is None:
            log("VERDICT: BLIND nothing dumped")
            return 1
        with open(BIN, "wb") as f:
            f.write(page)

        ents = list(struct.unpack_from("<512Q", page))
        pres = [i for i, v in enumerate(ents) if v & 1]
        log("present=%d/512" % len(pres))
        for b in range(8):
            n = sum(1 for i in pres if b * 64 <= i < b * 64 + 64)
            log("  band %d..%d present=%d" % (b * 64, b * 64 + 63, n))
        if pres:
            al2m = sum(1 for i in pres if not ((ents[i] >> 12) << 12) & 0x1FFFFF)
            al4k = sum(1 for i in pres if not ((ents[i] >> 12) << 12) & 0xFFF)
            log("present & 2MiB-aligned=%d (of %d), 4KiB-aligned=%d"
                % (al2m, len(pres), al4k))
            tgt_hi = [ents[i] >> 12 for i in pres]
            for bit in (5, 6, 7, 8, 9, 10, 11, 12):
                log("  bit %2d set on %d present entries" % (bit,
                    sum(1 for i in pres if ents[i] >> bit & 1)))
            for i in (0, 1, 2, 255, 256, 511):
                log("  [%3d] = %016x %s" % (i, ents[i],
                                            "PRESENT" if ents[i] & 1 else "-"))
            log("  first8 = %s" % " ".join("%016x" % ents[i] for i in range(8)))
            hi = [x for x in tgt_hi if x >= 0x100000]
            log("  pfn min=%#x max=%#x  (>1MiB: %d)"
                % (min(tgt_hi), max(tgt_hi), len(hi)))
            if len(pres) and al2m * 2 >= len(pres):
                log("VERDICT: looks like a PD (2 MiB leaves) -- not a PML4")
            elif ents[255] & 1 and (ents[255] >> 12) & 0xFFF == 0:
                log("VERDICT: entry 255 present+aligned, but density looks like a "
                    "leaf table -- PML4 only if the children decode as PDPTs")
            else:
                log("VERDICT: PML4-shaped but entry 255 absent -- suspect a leaf table")
        for pa in NEIGH:
            try:
                g.read_phys(pa, PAGE)
                log("neigh %#x OK ram=%s" % (pa, g.is_ram(pa)))
            except OSError as e:
                log("neigh %#x err %d" % (pa, e.args[0] if e.args else -1))
    log("dumped %s (%d bytes)" % (BIN, PAGE))
    return 0


if __name__ == "__main__":
    sys.exit(main())
