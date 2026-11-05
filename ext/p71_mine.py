"""p71_mine.py -- offline: find position-like float triples in a p61_live DUMP log.

Usage: python ext\p71_mine.py --log=temp\p70_log.txt [--max=60]
Read-only, no driver.  Prints triples (a, a+4, a+8) whose three f0 streams
drift in the same direction over the shots -- that is what a vec3 does.
"""
import struct
import sys


def f(u):
    return struct.unpack("<f", struct.pack("<I", u))[0]


def mono(seq):
    """count direction reversals of nonzero deltas"""
    d = [b - a for a, b in zip(seq, seq[1:]) if b != a]
    return sum(1 for x, y in zip(d, d[1:]) if (x > 0) != (y > 0))


def main(argv):
    log, mx = None, 60
    for a in argv:
        if a.startswith("--log="):
            log = a[6:]
        elif a.startswith("--max="):
            mx = int(a[6:])
    if not log:
        print("usage: p71_mine.py --log=path [--max=60]")
        return 2
    d = {}
    with open(log, "r", encoding="utf-16", errors="replace") as h:
        for line in h:
            if not line.startswith("DUMP "):
                continue
            x = line.split()
            try:                            # x[4:] -- x[3] is the f0=%g field
                vals = [int(v) for v in x[4:]]
            except ValueError:              # '-' = page missed that shot
                continue
            if len(vals) >= 6:
                d[int(x[1], 16)] = vals
    print("dump=%d" % len(d))
    n = 0
    for a in sorted(d):
        t = (a, a + 4, a + 8)
        if not all(k in d for k in t):
            continue
        if any(len(set(d[k])) < 2 for k in t):
            continue
        fl = [f(d[k][0]) for k in t]
        if not all(-100000.0 < v < 100000.0 for v in fl):
            continue
        if sum(1 for k in t if mono(d[k]) <= 1) < 2:
            continue
        print("TRIPLE %#011x f0=%s  %s" % (
            a, " ".join("%.3f" % v for v in fl),
            " | ".join("%.3f" % f(v) for v in d[a][:6])))
        n += 1
        if n >= mx:
            break
    print("TRIPLES %d" % n)
    return 0 if n else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
