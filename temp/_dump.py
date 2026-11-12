r"""_dump.py -- copy a line range of one file to another, so a range read never
depends on shell quoting.  Usage: _dump.py IN FROM TO OUT  (1-based, inclusive)
"""
import sys

src, a, b, dst = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
with open(src, encoding="utf-8", errors="replace") as f:
    lines = f.readlines()
with open(dst, "w", encoding="utf-8") as f:
    f.write("".join(lines[a - 1:b]))
print("%s lines %d..%d -> %s (%d lines)" % (src, a, b, dst, max(0, min(b, len(lines)) - a + 1)))
