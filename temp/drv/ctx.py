"""ctx.py -- print N lines of context around every match of a regex.

usage:  python ctx.py <file> <regex> [before] [after]
"""
import io
import re
import sys

path, pat = sys.argv[1], sys.argv[2]
before = int(sys.argv[3]) if len(sys.argv) > 3 else 8
after = int(sys.argv[4]) if len(sys.argv) > 4 else 14

lines = io.open(path, encoding="utf-8", errors="replace").read().splitlines()
rx = re.compile(pat)
out, last = [], -1
for i, ln in enumerate(lines):
    if not rx.search(ln):
        continue
    lo, hi = max(0, i - before), min(len(lines), i + after + 1)
    if lo <= last:                       # overlap -> only the new tail
        lo = last + 1
    if lo >= hi:
        continue
    out.append("; ---- match @ line %d ----" % (i + 1))
    out.extend(lines[lo:hi])
    last = hi - 1

sys.stdout.reconfigure(encoding="utf-8")
print("\n".join(out) if out else "; no match")
