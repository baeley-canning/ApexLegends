r"""p53_padump.py -- dump whole physical pages around a hit, pure reads.

dumplive.py's --lo/--hi restricts its *EPROCESS name scan*, not what it dumps,
so it cannot fetch a page window on its own.  This tool takes the PA directly:
no EPROCESS, no page tables, no MZ check.  ~1 s for a dozen pages.

Hit PAs from the sweep are marked in place ('<' at the hit byte in the hex
column, '*' on the row) so the field offsets around a needle are visible
without a second pass.

Usage:
  p53_padump.py --pa=0x70710d000 --pages=20 --hit=0x70711db40 --hit=0x70711ddc0
                [--label=fdb] [--out=path]     (default temp\p53_dump_<ts>[_label].txt)
Read-only: device open only.  Unreadable pages are reported, never fatal.
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

PAGE = 0x1000
MAXPAGES = 64
ROW = 16


def log(rows, s):
    rows.append(s)
    print(s)


def hexrow(pa, data, hits):
    out = []
    for off in range(0, len(data), ROW):
        chunk = data[off:off + ROW]
        cells = []
        star = False
        for i, b in enumerate(chunk):
            if (pa + off + i) in hits:
                cells.append("<%02x" % b)   # 3 chars, column stays aligned
                star = True
            else:
                cells.append(" %02x" % b)
        ascii_ = "".join(chr(b) if 0x20 <= b <= 0x7E else "." for b in chunk)
        out.append("    %06x %s |%s|%s" % (off, "".join(cells), ascii_,
                                           "  *" if star else ""))
    return out


def main(argv):
    pa = pages = None
    out_path = None
    label = ""
    hits = set()
    for a in argv:
        if a.startswith("--pa=0x"):
            pa = int(a[5:], 16)
        elif a.startswith("--pages="):
            pages = int(a[8:])
        elif a.startswith("--hit=0x"):
            hits.add(int(a[6:], 16))
        elif a.startswith("--label="):
            label = a[8:]
        elif a.startswith("--out="):
            out_path = a[6:]
    if not out_path:                       # never default to a shared name: a later
        tag = ("_" + label) if label else ""   # run must not overwrite raw pages
        out_path = os.path.join(os.path.dirname(HERE), "temp",
                                "p53_dump_%s%s.txt" % (time.strftime("%Y%m%d_%H%M%S"), tag))
    if pa is None or pages is None:
        print("usage: p53_padump.py --pa=0x.. --pages=N --hit=0x.. [--out=path]")
        return 2
    if pages < 1 or pages > MAXPAGES:
        print("pages must be 1..%d" % MAXPAGES)
        return 2
    rows = []
    log(rows, "# p53_padump %s label=%s pa=%#x pages=%d hits=%d"
        % (time.strftime("%Y-%m-%d %H:%M:%S"), label or "-", pa, pages, len(hits)))
    try:
        g = gio.Gio()
    except OSError as e:
        log(rows, "FATAL: %s" % e)
        log(rows, "VERDICT: FATAL no transport")
        _write(out_path, rows)
        return 1
    log(rows, "ram_top=%#x" % g.ram_top)
    t0 = time.perf_counter()
    ok = fault = 0
    seen_hits = 0
    used = 0
    for n in range(pages):
        p = pa + n * PAGE
        if not g.is_ram(p):
            log(rows, "SKIP  pa=%#x not RAM" % p)
            continue
        used += 1
        try:
            data = g.read_phys_checked(p, PAGE)
        except OSError as e:
            fault += 1
            log(rows, "FAULT pa=%#x err=%s" % (p, e))
            continue
        ok += 1
        mine = {h for h in hits if p <= h < p + PAGE}
        seen_hits += len(mine)
        log(rows, "PAGE  pa=%#x hits=%d" % (p, len(mine)))
        for line in hexrow(p, data, hits):
            rows.append(line)
    dt = time.perf_counter() - t0
    log(rows, "")
    log(rows, "readback %d pages ok=%d fault=%d hits_marked=%d/%d %.2fs"
        % (used, ok, fault, seen_hits, len(hits), dt))
    verdict = "PADUMP ok=%d fault=%d hits=%d/%d lo=%#x hi=%#x %.2fs" % (
        ok, fault, seen_hits, len(hits), pa, pa + pages * PAGE, dt)
    log(rows, "VERDICT: " + verdict)
    g.close()
    _write(out_path, rows)
    return 0 if ok and seen_hits == len(hits) else (4 if ok else 3)


def _write(path, rows):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(rows) + "\n")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
