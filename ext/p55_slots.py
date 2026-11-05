"""p55_slots.py -- widen one hit page into a multi-record window and measure
the entity record pitch directly.

The sweep only ever lands one or two needles per page; the pitch needs many
records visible at once.  This reads a whole page range, finds every
u32len+name+NUL signature blob, and reports
  (a) deltas between consecutive names -> stride histogram,
  (b) every slot with its surrounding qword lanes tagged h/f/k/u/a.
Read-only, device open only, faults are skipped per page.

Usage: p55_slots.py --page=0x626ea2000 [--span=0x40000] [--out=temp/p55_slots.txt]
"""
import os
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

ROOT = os.path.dirname(HERE)
PAGE = 0x1000
SPAN_DEF = 0x40000
MAXSPAN = 0x400000
SIG = re.compile(rb"[\x20-\x7e]{4,40}\x00")
LOG = []


def log(s):
    LOG.append(s)
    print(s)


def lane_tags(q):
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
    elif 0x10000 <= v <= 0x7FFFFFFFFFFF:
        tags.append("u")
    if all(0x20 <= c < 0x7F for c in q if c) and any(q):
        tags.append("a")
    return "".join(sorted(set(tags)))


def wr(path, code, verdict):
    log("VERDICT: %s" % verdict)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(LOG) + "\n")
    return code


def main(argv):
    pa = None
    span = SPAN_DEF
    out = os.path.join(ROOT, "temp", "p55_slots.txt")
    for a in argv:
        if a.startswith("--page=0x"):
            pa = int(a[7:], 16)
        elif a.startswith("--span=0x"):
            span = min(int(a[7:], 16), MAXSPAN)
        elif a.startswith("--out="):
            out = a[6:]
    if pa is None:
        print("usage: p55_slots.py --page=0x.. [--span=0x..] [--out=path]")
        return 2
    pa &= ~(PAGE - 1)
    log("# p55_slots %s page=%#x span=%#x" % (time.strftime("%Y-%m-%d %H:%M:%S"), pa, span))
    try:
        g = gio.Gio()
    except OSError as e:
        log("FATAL: %s" % e)
        return wr(out, 3, "FATAL no transport")
    blk = bytearray()
    ok = fault = 0
    for off in range(0, span, PAGE):
        p = pa + off
        try:
            blk += g.read_phys_checked(p, PAGE)
            ok += 1
        except OSError:
            blk += b"\x00" * PAGE
            fault += 1
    g.close()
    log("readback pages ok=%d fault=%d" % (ok, fault))

    found = []
    for m in SIG.finditer(blk):
        s = m.group()[:-1]
        if m.start() < 4:
            continue
        n = struct.unpack_from("<I", blk, m.start() - 4)[0]
        if n != len(s) or n > 0x30:
            continue
        found.append((m.start(), s))
    log("slots=%d" % len(found))
    if not found:
        return wr(out, 1, "NO_SLOTS")

    deltas = {}
    for (o1, _), (o2, _) in zip(found, found[1:]):
        d = o2 - o1
        if 0 < d < 0x4000:
            deltas[d] = deltas.get(d, 0) + 1
    log("")
    log("consecutive-name deltas:")
    ranked = sorted(deltas.items(), key=lambda kv: (-kv[1], kv[0]))
    for d, c in ranked[:10]:
        log("  %#x x%d%s" % (d, c, "  <= PITCH" if c > 1 else ""))

    log("")
    for off, s in found:
        pa_hit = pa + off
        pre = bytes(blk[off - 0x30:off])
        post = bytes(blk[off + len(s):off + len(s) + 0x40])
        ctx = ""
        for lane in range(-0x30, 0x18, 8):
            q = bytes(blk[off + lane:off + lane + 8])
            ctx += " %+03x:%s" % (lane, lane_tags(q))
        log("SLOT pa=%#x len=%#x %r  pre=%s post=%s lanes:%s"
            % (pa_hit, len(s), s.decode("ascii", "replace"), pre.hex(),
               post.hex(), ctx))

    top = ranked[0] if ranked else (0, 0)
    if top[1] > 1:
        return wr(out, 0, "PITCH cand=%#x x%d slots=%d" % (top[0], top[1], len(found)))
    return wr(out, 1, "NO_STRIDE slots=%d" % len(found))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
