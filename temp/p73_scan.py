r"""p73_scan.py -- one RAM pass, three content modes.  Read-only.

  --mode=img                    page starts MZ + PE + SizeOfImage > 64 MiB
  --mode=peb                    page+0x10 == ImageBaseAddress, Peb VA nearby
  --mode=pat --pa=.. --idx=N    qword at page+(N*8) whose PFN == pa, present,
                                PS clear (page-table-entry search, bottom-up)

Every hit is re-verified with a full 8-byte read of the same page.  Faulted
chunks fall back to per-page reads so one dead frame cannot end the pass.
Range plan is dumplive's usable_ranges (driver map minus BADPA).
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
IMGBASE = 0x7FF66ADC0000
PEBVA = 0x364000
NEAR = 0x10000000

MODE = {"mode": "img", "pa": 0, "idx": 0}
OUT = ""


def canon(q):
    return 0x10000 <= q < 0x800000000000


def check_pat(buf, off, page_pa):
    """page-table-entry test: qword at idx*8 must point at MODE['pa']."""
    q = struct.unpack_from("<Q", buf, off + MODE["idx"] * 8)[0]
    if q & 1 and not q & 0x80 and (q & 0x000FFFFFFFFFF000) == MODE["pa"]:
        return "pte idx=%d %#x flags=%#x" % (MODE["idx"], q, q & 0xFFF)
    return None


def check_img(buf, off, page_pa):
    if buf[off:off + 2] != b"MZ":
        return None
    e = struct.unpack_from("<I", buf, off + 0x3C)[0]
    if e & 3 or e > 0x400 or e + 0x60 > PAGE:
        return None
    if buf[off + e:off + e + 4] != b"PE\0\0":
        return None
    size = struct.unpack_from("<I", buf, off + e + 0x50)[0]
    if size < 0x4000000:
        return None
    return "pe sizeimg=%#x" % size


def check_peb(buf, off, page_pa):
    if buf[off + 2] > 1 or buf[off] > 1:
        return None
    q = struct.unpack_from("<Q", buf, off + 0x10)[0]
    if q != IMGBASE:
        return None
    ldr = struct.unpack_from("<Q", buf, off + 0x18)[0]
    par = struct.unpack_from("<Q", buf, off + 0x20)[0]
    for v in (ldr, par):
        if not canon(v) or abs(v - PEBVA) > NEAR:
            return None
    return "peb ldr=%#x par=%#x" % (ldr, par)


CHECKS = {"img": check_img, "peb": check_peb, "pat": check_pat}


def main():
    for a in sys.argv[1:]:
        if a.startswith("--mode="):
            MODE["mode"] = a[7:]
        elif a.startswith("--pa="):
            MODE["pa"] = int(a[5:], 0)
        elif a.startswith("--idx="):
            MODE["idx"] = int(a[6:], 0)
    check = CHECKS[MODE["mode"]]
    name = MODE["mode"]
    if MODE["mode"] == "pat":
        if not MODE["pa"] or not MODE["idx"]:
            print("pat needs --pa and --idx")
            return 2
        name = "pat_%x_%d" % (MODE["pa"], MODE["idx"])
    out = os.path.join(HERE, "p73_scan_%s.txt" % name)
    g = gio.Gio(chunk=CHUNK)
    hits = []
    faults = 0
    pages = 0
    t0 = time.time()
    try:
        ranges, note = dl.usable_ranges(g.ram_top)
        dl.log("scan %s ranges=%d %s" % (MODELABEL(MODE), len(ranges), note))
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
                    base = 0
                    while base < n:
                        r = check(blk, base, cur + base)
                        pages += 1
                        if r:
                            hits.append((cur + base, r))
                        base += PAGE
                else:
                    for base in range(0, n, PAGE):
                        try:
                            pg = g.read_phys(cur + base, PAGE)
                        except OSError:
                            continue
                        pages += 1
                        r = check(pg, 0, cur + base)
                        if r:
                            hits.append((cur + base, r))
                cur += n
    finally:
        g.close()
        el = time.time() - t0
        lines = ["%s pa=%#x idx=%d" % (MODE["mode"], MODE["pa"], MODE["idx"]),
                 "pages=%d faults=%d hits=%d %.1fs" % (pages, faults, len(hits), el)]
        for pa, why in hits:
            lines.append("%#x %s" % (pa, why))
        with open(out, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        print("\n".join(lines))
    return 0


def MODELABEL(m):
    return "%s pa=%#x idx=%d" % (m["mode"], m["pa"], m["idx"])


if __name__ == "__main__":
    sys.exit(main())
