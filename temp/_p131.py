r"""_p131.py -- PROBE p131: per-name delta map, name-anchored, +-0x2000.

p130 established two hard facts cheaply: a fresh cluster can be caught (9 s of sweep), and there
is NOTHING coordinate-shaped within 0x600 of the name.  p127 had "+-0x8000 with 1 byte alive"
because it straddled a freed block.  The live band has to be wide enough to hold a record and
narrow enough to stay inside one block.

p121's single real read on this build was at +0xF58, so the delta being looked for is ~0xF00.
This probe therefore does not look for a shared address at all: for each caught name it scans
its own +-0x2000 for a plausible triple and reports the SIGNED delta.  A layout that repeats for
players shows up as the same delta under two or three different names - that is the discriminator
p124's shared-address test could never see.

Everything is done inside one live pass, two reads 3 s apart, so a triple that also changed is
marked LIVE.  A delta that repeats across names AND is live is the answer.

Read-only, gdrv3 only.  Writes temp\_p131_out.txt.
RESULT:/VERDICT: name the variable (R5).  Usage: _p131.py [--secs=100]
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import gio
import dumplive as dl

OUT = os.path.join(HERE, "_p131_out.txt")
NEEDLES = ["kern30120", "spanner1981", "Gen X Gaming"]
CHUNK = 0x100000
BAND = 0x2000
GAP = 3


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def pl(v):
    return v == v and 1e-6 < abs(v) < 1e7


def ok(v):
    return (pl(v[0]) and pl(v[1]) and pl(v[2])
            and abs(v[0]) < 12000 and abs(v[1]) < 4000 and abs(v[2]) < 12000
            and (abs(v[0]) > 250 or abs(v[2]) > 250))


def triples(b):
    """{delta: (x,y,z)} for every plausible triple in the buffer"""
    out = {}
    for o in range(0, len(b) - 11, 4):
        v = struct.unpack("<fff", b[o:o + 12])
        if ok(v):
            out[o - BAND] = v
    return out


def band(g, pa):
    try:
        b = dl.retry_phys(g, pa - BAND, BAND * 2 + 16, tries=2)
    except Exception:                                          # noqa: BLE001
        return None
    return b if b and len(b) >= BAND * 2 else None



def main():
    secs = 100
    for a in sys.argv:
        if a.startswith("--secs="):
            secs = int(a.split("=", 1)[1])
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" --secs=%d' % (os.path.abspath(__file__), secs)))
        return 0
    open(OUT, "w").close()

    t0 = time.time()
    say("=== p131 per-name delta map %s band=%#x ===" % (time.strftime("%H:%M:%S"), BAND))
    pid = dl.find_pid()
    say("game_pid=%s" % pid)
    if pid is None:
        say("RESULT: game_pid=none")
        say("VERDICT: PARTIAL - game not running (R9)")
        return 3
    try:
        g = gio.Gio(chunk=CHUNK)
    except OSError as e:
        say("gio: %s" % e)
        return 2

    pats = {n: n.encode("ascii") for n in NEEDLES}
    ranges, rnote = dl.usable_ranges(g.ram_top, 0x1000, None)
    say("ranges=%d note=%s ram_top=%#x" % (len(ranges), rnote, g.ram_top))

    best = {}
    for rlo, rhi in ranges:
        pa = (rlo + 7) & ~7
        while pa + CHUNK <= rhi and time.time() - t0 < secs:
            try:
                blk = dl.retry_phys(g, pa, CHUNK, tries=1)
            except OSError:
                pa += 0x1000
                continue
            for n, p in pats.items():
                i = blk.find(p)
                while i >= 0:
                    best.setdefault(n, []).append(pa + i)
                    i = blk.find(p, i + 1)
            if len(best) == 3 and all(len(v) >= 3 for v in best.values()):
                break
            pa += CHUNK
        if len(best) == 3 and all(len(v) >= 3 for v in best.values()):
            break
    say("caught %.0fs hits=%s" % (time.time() - t0, {k: hex(v[0]) for k, v in best.items()}))
    if len(best) < 2:
        say("RESULT: names=%d" % len(best))
        say("VERDICT: FAIL - fewer than 2 names found, nothing to compare deltas across")
        return 1
    crowd = max(v[0] for v in best.values())
    picked = {}
    for n in list(best):
        a = min(best[n], key=lambda x: abs(x - crowd))
        if abs(a - crowd) <= 0x100:
            picked[n] = a
    say("record names=%d addrs=%s" % (len(picked), {k: hex(v) for k, v in picked.items()}))

    p1, p2 = {}, {}
    for n, a in picked.items():
        b = band(g, a)
        if b is not None:
            p1[n] = (a, b, triples(b))
    say("pass1 %s: %s" % (time.strftime("%H:%M:%S"), {k: len(v[2]) for k, v in p1.items()}))
    time.sleep(GAP)
    for n, a in picked.items():
        b = band(g, a)
        if b is not None:
            p2[n] = (a, b, triples(b))
    say("pass2 %s: %s" % (time.strftime("%H:%M:%S"), {k: len(v[2]) for k, v in p2.items()}))

    hist = {}
    for n, (a, b, t) in p1.items():
        say("--- %s %#x" % (n, a))
        for d, v in sorted(t.items())[:40]:
            live = d in p2.get(n, (0, b"", {}))[2]
            say("    d=%+#07x  %.2f %.2f %.2f%s"
                % (d, v[0], v[1], v[2], "  LIVE" if live else ""))
            hist[d] = hist.get(d, 0) + 1
        if len(t) > 40:
            say("    ... %d more" % (len(t) - 40))

    say("--- shared deltas (>=2 names) ---")
    shared = [(d, c) for d, c in sorted(hist.items(), key=lambda kv: -kv[1]) if c >= 2]
    for d, c in shared[:20]:
        vals = [(n, p1[n][2][d]) for n in p1 if d in p1[n][2]]
        live = [n for n, _v in vals if d in p2.get(n, (0, b"", {}))[2]]
        say("  d=%+#07x names=%d live=%d  %s"
            % (d, c, len(live),
               " ".join("%s(%.0f,%.0f,%.0f)" % (n[:6], v[0], v[1], v[2])
                        for n, v in vals)))

    say("RESULT: names=%d shared_deltas=%d" % (len(p1), len(shared)))
    if shared:
        d0, c0 = shared[0]
        say("VERDICT: PASS - %d names share delta %+#x: read a whole record, not a guessed address"
            % (c0, d0))
    else:
        say("VERDICT: FAIL - no delta repeats across names: names carry no coords in +-%#x" % BAND)
    return 0


if __name__ == "__main__":
    sys.exit(main())
