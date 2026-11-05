r"""p60_diff.py -- diff two p60_snap files, report dwords that changed.

Usage: python ext\p60_diff.py before after [--max=200]
An Apex health/shield field is a small int that drops by a known step when the
nade lands, so only decreases are printed, sorted by absolute delta.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(label):
    vals = {}
    with open(os.path.join(ROOT, "temp", "p60_snap_%s.txt" % label),
              "r", encoding="ascii", errors="replace") as f:
        for line in f:
            if line[0] == "#":
                continue
            parts = line.split()
            if len(parts) < 3:
                continue
            vals[int(parts[0], 16)] = (int(parts[1], 16), float(parts[2]))
    return vals


def main(argv):
    if len(argv) < 2:
        print("usage: p60_diff.py before after [--max=200]")
        return 2
    cap = 200
    for a in argv:
        if a.startswith("--max="):
            cap = int(a[6:])
    before, after = load(argv[0]), load(argv[1])
    drops = []
    for addr, (v0, f0) in before.items():
        cur = after.get(addr)
        if cur is None:
            continue
        v1 = cur[0]
        if v1 < v0:
            drops.append((v0 - v1, addr, v0, v1, f0, cur[1]))
    drops.sort(reverse=True)
    print("compared=%d dropped=%d" % (len(before), len(drops)))
    for d, addr, v0, v1, f0, f1 in drops[:cap]:
        print("DROP %#011x %d -> %d (%g -> %g) delta=%d" % (addr, v0, v1, f0, f1, d))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
