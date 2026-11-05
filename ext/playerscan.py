"""playerscan.py -- physical needle scanner for live-match player records.

A live match has dozens of distinct player names in the game heap, so the
anchor stops being a per-launch decoy and becomes *content*: scan RAM for the
ASCII (or UTF-16LE) of a name visible on the scoreboard / kill feed, and log
every PA with 96 bytes of context.  Two or three needles are the point -- a
page that holds two different names is an entity-array candidate, so the run
ends with a COOC summary of pages whose hits overlap.

Read-only: device open only, no driver load, no DSE, no service touch.  Chunk
faults are rescued at 4 KiB.  Bounded by --max-s and --max-hits, resumable with
--from, one hit per page per needle (--page-cap raises it).

--per-needle=N caps each needle separately and keeps scanning past the cap, so
the sweep still reaches the end of the window ("stopped=covered") instead of
dying at the first busy needle; the verdict then reports sat=<idx>:<hits>.

Usage:
  playerscan.py --needle=NameOne --needle=NameTwo [--dir=desc] [--max-s=150]
                [--lo=0x0eda00000 --hi=0x7eda00000 --ctx=96 --per-needle=1200]
  playerscan.py --hex=4e616d65 --u16 ...        (explicit encodings)
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
OUT = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_OUT", "p45_playerscan.txt"))
PROG = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_PROG", "p45_progress.txt"))
CTX_DEF = 96
MAXS_DEF = 150
MAXHITS_DEF = 400
PAGECAP_DEF = 2
PAGE = 0x1000

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


def wr(code, verdict):
    log("VERDICT: %s" % verdict)
    open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
    return code


def hexrow(blk, at, ctx):
    """Side-by-side hex/ascii of the context window, hit bytes marked."""
    lo = max(0, at - ctx)
    hi = min(len(blk), at + ctx)
    lines = []
    for base in range(lo, hi, 16):
        cut = blk[base:base + 16]
        hx = " ".join("%02x" % c for c in cut)
        tx = "".join(chr(c) if 0x20 <= c < 0x7F else "." for c in cut)
        lines.append("    %06x  %-47s  |%s|" % (base - lo, hx, tx))
    return lines


def parse():
    needles = []
    lo = hi = None
    ctx, max_s, max_hits, page_cap = CTX_DEF, MAXS_DEF, MAXHITS_DEF, PAGECAP_DEF
    per_needle = 0
    enc16 = False
    start = None
    desc = True
    for a in sys.argv[1:]:
        k, _, v = a.partition("=")
        if k == "--needle" and v:
            needles.append(("txt", v))
        elif k == "--hex" and v:
            needles.append(("hex", bytes.fromhex(v)))
        elif k == "--u16":
            enc16 = True
        elif k == "--lo":
            lo = int(v, 0)
        elif k == "--hi":
            hi = int(v, 0)
        elif k == "--from":
            start = int(v, 0)
        elif k == "--ctx":
            ctx = int(v, 0)
        elif k == "--max-s":
            max_s = float(v)
        elif k == "--max-hits":
            max_hits = int(v, 0)
        elif k == "--page-cap":
            page_cap = int(v, 0)
        elif k == "--per-needle":
            per_needle = int(v, 0)
        elif k == "--dir":
            desc = (v != "asc")
    pats = []
    for kind, v in needles:
        b = bytes.fromhex(v) if kind == "hex" else v.encode("utf-8")
        pats.append(b.encode("utf-16-le") if (enc16 and kind == "txt") else b)
    if per_needle > 0:
        max_hits = max(max_hits, per_needle * len(pats) + 16)
    return (pats, [v for _, v in needles], lo, hi, ctx, max_s, max_hits,
            page_cap, per_needle, start, desc)


def main():
    pats, names, lo, hi, ctx, max_s, max_hits, page_cap, per_needle, start, desc = parse()
    if not pats:
        return wr(4, "NO_NEEDLE")
    log("playerscan %s needles=%d enc16=%s dir=%s window=%s..%s max_s=%s"
        % (time.strftime("%Y-%m-%d %H:%M:%S"), len(pats), "--u16" in sys.argv,
           "desc" if desc else "asc", hex(lo) if lo else "auto",
           hex(hi) if hi else "auto", max_s))
    for i, (p, n) in enumerate(zip(pats, names)):
        log("  n=%d %r -> %d bytes" % (i, n, len(p)))
    try:
        g = gio.Gio(chunk=dl.SCAN_CHUNK)
        top = g.ram_top
    except OSError as e:
        log("FATAL: %s" % e)
        return wr(2, "FATAL no transport")

    ranges, note = dl.usable_ranges(top, lo, hi, None)
    log("RAMMAP %s top=%#x ranges=%d total=%d MiB"
        % (note, top, len(ranges), sum(b - a for a, b in ranges) >> 20))
    if desc:
        ranges = [(a, b) for a, b in reversed(ranges)]
    for a, b in ranges:
        prog("RANGE %#x-%#x" % (a, b))
    if not ranges:
        g.close()
        return wr(3, "NO_RANGES")

    hits = []                       # (needle_idx, pa, page)
    nhit = [0] * len(pats)
    full = per_needle > 0
    per_page = {}
    seen_pages = {}
    bad = rescued = 0
    scanned = 0
    nxt = dl.CKPT_BYTES
    stopped = "covered"
    t0 = time.perf_counter()
    CH = dl.SCAN_CHUNK

    def take(blk, base, blen):
        for ni, pat in enumerate(pats):
            if per_needle and nhit[ni] >= per_needle:
                continue
            off = 0
            while len(hits) < max_hits:
                i = blk.find(pat, off)
                if i < 0:
                    break
                off = i + 1
                if i + len(pat) > blen:
                    continue
                if per_needle and nhit[ni] >= per_needle:
                    break
                pa = base + i
                key = (pa & ~(PAGE - 1), ni)
                c = per_page.get(key, 0)
                if c >= page_cap:
                    continue
                per_page[key] = c + 1
                nhit[ni] += 1
                hits.append((ni, pa, key[0]))
                log("HIT n=%d pa=%#x page=%#x %r" % (ni, pa, key[0], names[ni]))
                for line in hexrow(blk, i, ctx):
                    log(line)
                prog("HIT n=%d pa=%#x" % (ni, pa))

    for rlo, rhi in ranges:
        al_lo = rlo & ~(CH - 1)
        al_hi = min(top, (rhi + CH - 1) & ~(CH - 1))
        pa = min(al_hi, top) - CH if desc else al_lo
        while (pa >= al_lo) if desc else (pa < al_hi):
            if start is not None:
                if (desc and pa > start) or (not desc and pa + CH <= start):
                    pa += -CH if desc else CH
                    continue
            n = min(CH, al_hi - pa)
            try:
                blk = g.read_phys(pa, n)
            except OSError:
                for sub in range(0, n, PAGE):
                    sn = min(PAGE, n - sub)
                    try:
                        sblk = g.read_phys(pa + sub, sn)
                    except OSError:
                        bad += 1
                        continue
                    rescued += 1
                    take(sblk, pa + sub, sn)
                scanned += n
                prog("FAULT pa=%#x bad4k=%d hits=%d" % (pa, bad, len(hits)))
            else:
                take(blk, pa, n)
                scanned += n
            if len(hits) >= max_hits and not full:
                stopped = "max_hits"
                break
            if scanned >= nxt:
                prog("CKPT pa=%#x scanned=%d MiB hits=%d bad=%d %.1fs"
                     % (pa, scanned >> 20, len(hits), bad,
                        time.perf_counter() - t0))
                nxt += dl.CKPT_BYTES
            if time.perf_counter() - t0 >= max_s:
                stopped = "max_s"
                break
            pa += -CH if desc else CH
        if stopped != "covered":
            break
    g.close()

    for ni, pa, page in hits:
        seen_pages.setdefault(page, set()).add(ni)
    cooc = [(p, s) for p, s in seen_pages.items() if len(s) > 1]
    log("")
    log("PAs %d hits over %d pages, %d MiB scanned in %.1fs bad4k=%d rescued=%d stopped=%s"
        % (len(hits), len(seen_pages), scanned >> 20, time.perf_counter() - t0,
           bad, rescued, stopped))
    sat = ",".join("%d:%d" % (i, n) for i, n in enumerate(nhit) if per_needle and n >= per_needle)
    log("PER-NEEDLE " + " ".join("n=%d:%d" % (i, n) for i, n in enumerate(nhit))
        + (" saturated=" + sat if sat else ""))
    log("COOC %d pages carry 2+ needles" % len(cooc))
    for p, s in sorted(cooc)[:40]:
        log("  COOC page=%#x needles=%s" % (p, ",".join(str(x) for x in sorted(s))))
    if not hits:
        return wr(0, "NO_HIT needles=%d scanned=%d MiB stopped=%s"
                  % (len(pats), scanned >> 20, stopped))
    return wr(0, "HITS=%d pages=%d cooc=%d scanned=%d MiB stopped=%s sat=%s first_n=%d first_pa=%#x"
              % (len(hits), len(seen_pages), len(cooc), scanned >> 20, stopped,
                 sat or "-", hits[0][0], hits[0][1]))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        import traceback
        log("CRASH %s: %s" % (type(e).__name__, e))
        log(traceback.format_exc().replace("\n", " | ")[:900])
        sys.exit(wr(9, "CRASH %s" % type(e).__name__))
