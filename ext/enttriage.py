"""enttriage.py -- turn playerscan COOC pages into an entity candidate.

playerscan only says "this page holds two different player names".  A page with
two names is either an entity-array page or a coincidence (scoreboard UI, chat),
so this stage reads each such page once with span on both sides and reports the
shape of every hit: qword lanes tagged as health-range dword (`h`), coordinate-
range float (`f`), kernel VA (`k`), user VA (`u`), or ASCII (`a`).  Then it
measures the deltas between hits of *different* needles and reports any delta
that repeats -- a repeating delta is the record stride and the array is real.

Read-only.  Usage: enttriage.py --hits=_ritual/p47_hits.txt [--cap=12]
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
OUT = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_OUT", "p48_triage.txt"))
PROG = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_PROG", "p48_progress.txt"))
PAGE = 0x1000
SPAN_DEF = 0x2000
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
def lane_tags(q):
    """Tags for an 8-byte lane: h=health/shield dword, f=coord float,
    k=kernel VA, u=user VA, a=ASCII."""
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
    elif 0x10000 <= v <= 0x7FFFFFFFFFFF and v & 0xFFF < 0x1000:
        tags.append("u")
    if all(0x20 <= c < 0x7F for c in q if c) and any(0x20 <= c < 0x7F for c in q):
        tags.append("a")
    return "".join(sorted(set(tags)))


def parse_hits(path):
    pages, hits = {}, {}
    for line in open(path, encoding="utf-8", errors="replace"):
        if line.startswith("HIT "):
            f = dict(kv.split("=", 1) for kv in line.split()[1:] if "=" in kv)
            try:
                ni, pa, pg = int(f["n"]), int(f["pa"], 16), int(f["page"], 16)
            except KeyError:
                continue
            hits.setdefault(pg, []).append((ni, pa))
        elif line.startswith("  COOC page="):
            pg = int(line.split("page=", 1)[1].split()[0], 16)
            pages[pg] = True
    # richest pages first: a page holding every needle beats one holding two
    return sorted(pages, key=lambda p: (-len({n for n, _ in hits.get(p, ())}), p)), hits


def main():
    hits_path = os.path.join(ROOT, "_ritual", "p47_hits.txt")
    cap, span, names = 12, SPAN_DEF, [3]
    for a in sys.argv[1:]:
        k, _, v = a.partition("=")
        if k == "--hits":
            hits_path = os.path.abspath(v)
        elif k == "--cap":
            cap = int(v, 0)
        elif k == "--span":
            span = int(v, 0)
        elif k == "--needles":
            n = int(v, 0)
            names = [0] * n
    log("enttriage %s hits=%s" % (time.strftime("%Y-%m-%d %H:%M:%S"), hits_path))
    if not os.path.exists(hits_path):
        return wr(4, "NO_HITS_FILE")
    pages, hits = parse_hits(hits_path)
    multi = sum(1 for p in pages if len({n for n, _ in hits.get(p, ())}) == len(names))
    log("COOC pages=%d full_house=%d cap=%d" % (len(pages), multi, cap))
    if not pages:
        return wr(2, "NO_COOC")
    try:
        g = gio.Gio(chunk=dl.SCAN_CHUNK)
    except OSError as e:
        log("FATAL: %s" % e)
        return wr(3, "FATAL no transport")

    strides = {}
    for pg in pages[:cap]:
        try:
            blk = g.read_phys(pg - span, PAGE + 2 * span)
            base = pg - span
        except OSError:
            blk, base = bytearray(), pg
            for sub in range(0, PAGE + 2 * span, PAGE):
                try:
                    blk += g.read_phys(pg - span + sub, PAGE)
                except OSError:
                    blk += b"\x00" * PAGE
        log("")
        log("PAGE %#x hits=%d" % (pg, len(hits.get(pg, ()))))
        for ni, pa in hits.get(pg, ()):
            oc = pa - base
            if oc < 0x40 or oc + 0x48 > len(blk):
                log("  hit n=%d pa=%#x out of window" % (ni, pa))
                continue
            log("  hit n=%d pa=%#x oc=%#x" % (ni, pa, oc))
            for lane in range(-0x40, 0x48, 8):
                q = bytes(blk[oc + lane:oc + lane + 8])
                v = struct.unpack("<Q", q)[0]
                log("    %+04x %016x %-3s %s" % (lane, v, lane_tags(q),
                                                  repr(q)[2:-1]))
        own = hits.get(pg, ())
        for i in range(len(own)):
            for j in range(i + 1, len(own)):
                if own[i][0] == own[j][0]:
                    continue
                d = abs(own[i][1] - own[j][1])
                strides[d] = strides.get(d, 0) + 1
    g.close()
    log("")
    # count first; on ties, an aligned delta of plausible record size wins over
    # coincidence-shaped ones (0x9, page-boundary 0x800)
    def rank(kv):
        d, c = kv
        fit = 1 if (d % 8 == 0 and 0x20 <= d <= 0x4000) else 0
        return (-c, -fit, d)
    ranked = sorted(strides.items(), key=rank)
    log("delta histogram (cross-needle):")
    for d, c in ranked[:12]:
        log("  %#x x%d%s" % (d, c, "  <= STRIDE CANDIDATE" if c > 1 else ""))
    rep = [(d, c) for d, c in ranked if c > 1]
    if not pages:
        return wr(5, "NO_PAGES_READ")
    if rep:
        return wr(0, "STRIDE cand=%d x%d pages=%d" % (rep[0][0], rep[0][1], len(pages)))
    return wr(1, "COOC_ONLY pages=%d no repeating delta" % len(pages))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        import traceback
        log("CRASH %s: %s" % (type(e).__name__, e))
        log(traceback.format_exc().replace("\n", " | ")[:900])
        sys.exit(wr(9, "CRASH %s" % type(e).__name__))

