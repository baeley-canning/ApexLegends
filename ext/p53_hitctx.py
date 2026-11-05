r"""p53_hitctx.py -- sweep + immediate context dump, in one process, text pages dropped.

Every needle string also exists in RAM as cached file text (ext/p53_rehit.py,
temp/*.txt, _ritual/*.txt), so a plain sweep saturates on its own logs; those
pages are then reclaimed and a later re-read lands on zeros or unrelated dwords.
Confirmed 2026-11-04: p52 fixture PAs 0x7e7a7b8* now read unrelated binary,
0x7e955* fault (ERROR_NO_SYSTEM_RESOURCES), 0x7abc3d800 (names at 16:52) is
zeroed by 17:02.

So the sweep must (a) drop text pages, (b) render context out of the buffer that
produced the match -- never re-read, and (c) optionally demand the p52 record
signature: u32 LE length before the name, NUL right after it.

Hits and their context rows are flushed to disk as they are found, so a 0x124
mid-run no longer eats the corpus (the 17:04 run died before writing at all).

Usage: p53_hitctx.py [--lo=hex] [--hi=hex] [--max=8] [--sig] [--max_s=45] [--out=path]
Default --out is temp\p53_hitctx_<timestamp>.txt -- runs never overwrite each other.
Read-only.
"""
import os
import sys
import time


HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

NEEDLES = os.path.join(os.path.dirname(HERE), "temp", "p53_needles.txt")
OUT = os.path.join(os.path.dirname(HERE), "temp",
                   "p53_hitctx_%s.txt" % time.strftime("%Y%m%d_%H%M%S"))
BEFORE = 64
AFTER = 192
CHUNK = 0x10000
PAGE = 0x1000
TEXT_MAX = 0.5
PRINT = bytes(range(0x20, 0x7F)) + b"\t\n\r"


def load_needles(path):
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s and not s.startswith("#"):
                out.append(s.encode("ascii", "replace"))
    return out


def ascii_ratio(b):
    if not b:
        return 1.0
    return sum(1 for x in b if x in PRINT) / len(b)


def render(base, blk, origin, hit, first, last):
    """origin = index in blk where address `base` begins (the page)."""
    rows = []
    for off in range(first, last, 16):
        s = origin + off
        chunk = blk[max(0, s):max(0, s) + 16]
        if not chunk:
            break
        cells, star = [], False
        for i, b in enumerate(chunk):
            if base + off + i == hit:
                cells.append("<%02x" % b)
                star = True
            else:
                cells.append(" %02x" % b)
        asc = "".join(chr(b) if 0x20 <= b <= 0x7E else "." for b in chunk)
        rows.append("    %06x %s |%s|%s" % (off, "".join(cells), asc,
                                            "  *" if star else ""))
    return rows


def main(argv):
    lo, hi, maxhits, out_path = 0x0eda00000, 0x7eda00000, 8, OUT
    max_s, need_sig, per_page = 45.0, False, 2
    for a in argv:
        if a.startswith("--lo="):
            lo = int(a[5:], 16)
        elif a.startswith("--hi="):
            hi = int(a[5:], 16)
        elif a.startswith("--max="):
            maxhits = int(a[6:])
        elif a.startswith("--max_s="):
            max_s = float(a[8:])
        elif a == "--sig":
            need_sig = True
        elif a.startswith("--perpage="):
            per_page = int(a[10:])
        elif a.startswith("--out="):
            out_path = a[6:]
    pats = load_needles(NEEDLES)
    log = []
    fh = open(out_path, "w", encoding="utf-8")

    def emit(s):
        """Flush every line: a bugcheck mid-run must not eat the evidence."""
        log.append(s)
        fh.write(s + "\n")
        fh.flush()

    emit("# p53_hitctx %s pid=%d range=%#x-%#x needles=%d sig=%s out=%s"
         % (time.strftime("%Y-%m-%d %H:%M:%S"), os.getpid(), lo, hi, len(pats),
            need_sig, out_path))
    try:
        g = gio.Gio()
    except OSError as e:                   # same shape as padump: fatal, but a verdict
        emit("FATAL: %s" % e)
        emit("VERDICT hits=0 cooc_pages=0 secs=0.0 max_s=%.0f fatal=no-transport out=%s"
             % (max_s, out_path))
        fh.close()
        print(log[-1])
        return 1
    t0 = time.time()
    found = scanned = 0
    seen = {}
    pa = hi - CHUNK
    while pa >= lo and found < maxhits and time.time() - t0 < max_s:
        try:
            blk = g.read_phys(pa, CHUNK)
        except OSError:
            pa -= CHUNK
            continue
        scanned += 1
        for ni, pat in enumerate(pats):
            n = len(pat)
            i = blk.find(pat)
            while i >= 0 and found < maxhits:
                hit = pa + i
                page = hit & ~(PAGE - 1)
                poff = page - pa
                nxt = blk.find(pat, i + 1)
                if (len(blk) - poff) < PAGE:
                    i = nxt
                    continue
                pdat = blk[poff:poff + PAGE]
                if ascii_ratio(pdat) > TEXT_MAX:
                    i = nxt
                    continue
                term = pdat[hit - page + n:hit - page + n + 1] == b"\0"
                pre = blk[i - 4:i] if i >= 4 else b""
                lpm = (len(pre) == 4 and int.from_bytes(pre, "little") == n)
                if need_sig and not (term and lpm):
                    i = nxt
                    continue
                if seen.get(page, 0) >= per_page:
                    i = nxt
                    continue
                seen[page] = seen.get(page, 0) + 1
                pstart = hit - page
                emit("HIT n=%d pa=%#x page=%#x pre4=%s len=0x%x lp=%s nul=%s %r"
                     % (ni, hit, page, pre[::-1].hex(), n, lpm, term,
                        pat.decode()))
                first = max(0, pstart - BEFORE)
                last = min(PAGE, pstart + AFTER)
                for r in render(page, blk, poff, hit, first, last):
                    emit(r)
                found += 1
                i = nxt
        pa -= CHUNK
    g.close()
    for pg in sorted(seen):
        emit("  COOC page=%#x hits=%d" % (pg, seen[pg]))
    emit("hits=%d chunks=%d pages=%d secs=%.1f"
         % (found, scanned, len(seen), time.time() - t0))
    emit("VERDICT hits=%d cooc_pages=%d secs=%.1f max_s=%.0f out=%s"
         % (found, len(seen), time.time() - t0, max_s, out_path))
    fh.close()
    print("\n".join(log[:6]))
    print(log[-1])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
