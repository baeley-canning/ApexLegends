r"""_p125.py -- PROBE p125: stop offset-poking.  Chase the pointer to the object.

p124 measured it: a three-name cluster can be all three party names inside 0x100 and still
have NO plausible world position within +-0x3000.  So the name is not a field of a player
struct on this build - the old name-0xEEC only worked on a build where it was.  Every
delta probe since p116 was therefore poking the wrong region.

What must be true instead: some object holds a POINTER to the object that owns the name
(roster entry -> entity), or the name slot is a pointer itself.  This probe reads around
each name hit and follows every heap-looking qword, then asks the only question that
matters: does the target contain this needle again?  A hit that does is an entity
candidate, and the offset becomes measurable by dumping it, not by guessing.

Read-only, gdrv3 only.  Writes temp\_p125_out.txt, _p125_links.txt.
RESULT:/VERDICT: name the variable (R5).  Usage: _p125.py [--hits=60] [--secs=110]
"""
import math
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import _p116 as P  # noqa: E402

EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio              # noqa: E402
import dumplive as dl   # noqa: E402

OUT = os.path.join(HERE, "_p125_out.txt")
LINK = os.path.join(HERE, "_p125_links.txt")
FLOOR = 0x140000000
NEEDLES = ["kern30120", "BurntRice", "BallSharpener"]
WIN = 0x400          # how far around the hit to look for pointers
PROBE = 0x80         # bytes read at each pointer target
PER_BLOCK = 2        # hits taken per 64K block, so the sample spreads over the sweep


def say(s):
    line = "".join(c if ord(c) < 128 else "?" for c in str(s))
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def ptrs(w, lo, ram_top):
    """Heap-looking 8-aligned qwords in w, as absolute addresses."""
    out = []
    for i in range(0, len(w) - 8, 8):
        q = struct.unpack("<Q", w[i:i + 8])[0]
        if FLOOR <= q < ram_top and q % 8 == 0:
            out.append((lo + i, q))
    return out


def holds(g, pa, needle):
    try:
        b = dl.retry_phys(g, pa, PROBE, tries=1)
    except Exception:                                          # noqa: BLE001
        return None
    for enc in ("ascii", "utf-16-le"):
        if needle.encode(enc) in b:
            return enc
    return None


def main():
    hits_n, secs = 60, 110
    for a in sys.argv:
        if a.startswith("--hits="):
            hits_n = int(a.split("=", 1)[1])
        elif a.startswith("--secs="):
            secs = int(a.split("=", 1)[1])
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" --hits=%d --secs=%d'
                            % (os.path.abspath(__file__), hits_n, secs)))
        return 0
    for p in (OUT, LINK):
        open(p, "w").close()
    say("=== p125 pointer chase %s hits=%d win=%#x ==="
        % (time.strftime("%H:%M:%S"), hits_n, WIN))
    pid = dl.find_pid()
    say("game_pid=%s" % pid)
    if pid is None:
        say("RESULT: game_pid=none")
        say("VERDICT: PARTIAL - game not running (R9)")
        return 3
    try:
        g = gio.Gio(chunk=P.CHUNK)
    except OSError as e:
        say("gio: %s" % e)
        return 2
    ranges, rnote = dl.usable_ranges(g.ram_top, FLOOR, None)
    say("ranges=%d note=%s ram_top=%#x" % (len(ranges), rnote, g.ram_top))
    pats = {n: (n.encode("utf-16-le"), n.encode("ascii")) for n in NEEDLES}
    raw = 0
    links, seen = [], set()
    t0 = time.time()
    try:
        for rlo, rhi in ranges:
            pa = (rlo + 7) & ~7
            while pa + P.CHUNK <= rhi and raw < hits_n and time.time() - t0 < secs:
                try:
                    blk = dl.retry_phys(g, pa, P.CHUNK, tries=1)
                except OSError:
                    pa += 0x1000
                    continue
                perblk = 0
                for n in NEEDLES:
                    for pat in pats[n]:
                        k = blk.find(pat)
                        while k >= 0 and raw < hits_n:
                            a = pa + k
                            k = blk.find(pat, k + 1)
                            if a in seen:
                                continue
                            seen.add(a)
                            if perblk >= PER_BLOCK:
                                continue
                            perblk += 1
                            raw += 1
                            lo = max(rlo, a - WIN)
                            try:
                                w = dl.retry_phys(g, lo, (a - lo) + WIN, tries=1)
                            except Exception:                      # noqa: BLE001
                                continue
                            for src, tgt in ptrs(w, lo, g.ram_top):
                                enc = holds(g, tgt, n)
                                if enc is None:
                                    continue
                                links.append({"name": n, "hit": a, "src": src,
                                              "tgt": tgt, "enc": enc})
                                say("  LINK %-15s hit=%#x slot=%#x -> %#x (%s, %d ap)"
                                    % (n, a, src, tgt, enc, tgt - a))
                pa += P.CHUNK
                if raw and raw % 10 == 0:
                    say("  prog %s raw=%d links=%d (%.0fs)"
                        % (time.strftime("%H:%M:%S"), raw, len(links), time.time() - t0))
    finally:
        g.close()
    with open(LINK, "w") as f:
        for r in links:
            f.write("%s %#x %#x %#x %s\n"
                    % (r["name"], r["hit"], r["src"], r["tgt"], r["enc"]))
    names = {r["name"] for r in links}
    deltas = {}
    for r in links:
        d = r["src"] - r["hit"]
        deltas[r["tgt"] - r["src"]] = deltas.get(r["tgt"] - r["src"], 0) + 1
    top = sorted(deltas.items(), key=lambda kv: -kv[1])[:6]
    say("RESULT: raw_hits=%d links=%d names=%d slot_deltas=%d"
        % (raw, len(links), len(names), len(set(deltas))))
    say("       slot->target top: %s" % " ".join("%+#x:%d" % kv for kv in top))
    if links:
        say("VERDICT: PASS - %d pointer(s) lead from a name slot to an object holding it "
            "again; recurse from the target, do not poke the name" % len(links))
    else:
        say("VERDICT: FAIL - no heap pointer near a name hit resolves to an object "
            "holding that name")
    return 0


if __name__ == "__main__":
    sys.exit(main())

