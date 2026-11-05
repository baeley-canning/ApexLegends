r"""p73_imgval.py -- every occurrence of the image-base qword in RAM, with the
two qwords after it.  Read-only; the PEB shows up as hit at page+0x10 whose
+0x08/+0x10 are canonical VAs close to the PEB.
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio
import dumplive as dl

CHUNK = 0x10000
PAGE = 0x1000
PAT = struct.pack("<Q", 0x7FF66ADC0000)
PEBVA = 0x364000
NEAR = 0x20000000
OUT = os.path.join(HERE, "_p73_imgval.txt")


def canon(q):
    return 0x10000 <= q < 0x800000000000


def main():
    lines = []
    g = gio.Gio(chunk=CHUNK)
    hits = []
    faults = 0
    t0 = time.time()
    try:
        ranges, note = dl.usable_ranges(g.ram_top)
        lines.append("ranges=%d %s" % (len(ranges), note))
        for lo, hi in ranges:
            cur = lo
            while cur < hi:
                n = min(CHUNK, hi - cur)
                try:
                    blk = g.read_phys(cur, n)
                except OSError:
                    faults += 1
                    blk = None
                if blk is not None:
                    p = blk.find(PAT)
                    while p >= 0 and len(hits) < 400:
                        hits.append(cur + p)
                        p = blk.find(PAT, p + 1)
                cur += n
    finally:
        g.close()
    # context pass
    lines.append("hits=%d faults=%d %.1fs" % (len(hits), faults, time.time() - t0))
    g = gio.Gio()
    try:
        for pa in hits:
            page = pa & ~0xFFF
            off = pa - page
            try:
                blk = g.read_phys(page, 0x100)
            except OSError:
                lines.append("%#x off=%#x page DEAD" % (pa, off))
                continue
            nxt = struct.unpack_from("<Q", blk, off + 8)[0] if off < 0xF8 else 0
            nxt2 = struct.unpack_from("<Q", blk, off + 0x10)[0] if off < 0xF0 else 0
            tag = ""
            if off == 0x10 and canon(nxt) and canon(nxt2):
                if abs(nxt - PEBVA) < NEAR and abs(nxt2 - PEBVA) < NEAR:
                    tag = " <== PEB"
                else:
                    tag = " canon-pair"
            lines.append("%#x off=%#x +8=%#x +10=%#x head=%s%s"
                         % (pa, off, nxt, nxt2, blk[:4].hex(), tag))
    finally:
        g.close()
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
