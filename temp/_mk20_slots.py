r"""_mk20_slots.py -- which float slot in a census record holds a world coordinate?

Offline, from _mk20_raw.txt only.  The census record is 0xC0 bytes of *something*;
before any matrix can be tested the coordinate slots have to be facts, not guesses.
A world coordinate in this game's maps is a few thousand units (never unit-length,
never 1e-40), so the slot that is "big and sane" across many records is the one.

  python temp\_mk20_slots.py
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "_mk20_raw.txt")
OUT = os.path.join(HERE, "_mk20_slots.txt")

LO, HI = 1.0, 40000.0


def load():
    recs = []
    with open(RAW, encoding="utf-8") as f:
        for line in f:
            t = line.split()
            if len(t) >= 3 and t[0] == "seed" and t[2] != "FAIL":
                recs.append((int(t[1], 16), bytes.fromhex(t[2])))
    return recs


def main():
    recs = load()
    out = []

    def w(s=""):
        out.append(s)
        print(s)

    w("# _mk20 slot census over %d record(s)" % len(recs))
    if not recs:
        w("no records")
        return 1
    n = min(len(b) // 4 for _, b in recs)
    hits = []
    for slot in range(n):
        cnt = 0
        for _, b in recs:
            v = struct.unpack_from("<f", b, slot * 4)[0]
            if v == v and LO <= abs(v) <= HI:
                cnt += 1
        hits.append((cnt, slot))
    hits.sort(reverse=True)
    w("")
    w("slots holding a big finite value (|v| in %g..%g), best first:" % (LO, HI))
    for cnt, slot in hits[:16]:
        w("   f%-3d +%#04x  %2d/%d" % (slot, slot * 4, cnt, len(recs)))
    keep = [s for c, s in hits if c >= max(3, len(recs) // 3)]
    w("")
    w("slots that could be coordinates: %s" % [("f%d" % s) for s in keep])

    w("")
    w("first 3 records, 48 floats (0xC0):")
    for pa, b in recs[:3]:
        f = struct.unpack_from("<48f", b, 0)
        w("  %#011x" % pa)
        for i in range(0, 48, 6):
            w("     %s" % " ".join("%11.5g" % v for v in f[i:i + 6]))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
