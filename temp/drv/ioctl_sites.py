"""ioctl_sites.py -- list every DeviceIoControl call site of a PE with a
window of preceding instructions, so the IOCTL code (edx/r9d immediate or
stack slot) and the in/out buffer setup can be read off.
"""
import io
import os
import re
import sys

path = sys.argv[1]
lines = io.open(path, encoding="utf-8").read().splitlines()
win = int(sys.argv[2]) if len(sys.argv) > 2 else 26
out = []
for i, ln in enumerate(lines):
    if "DeviceIoControl" in ln:
        for j in range(max(0, i - win), min(len(lines), i + 6)):
            out.append(("* " if j == i else "  ") + lines[j])
        out.append("")
dst = os.path.join(os.path.dirname(os.path.abspath(path)), "ioctl_sites.txt")
io.open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
print("wrote %s (%d sites)" % (dst, sum(1 for l in out if l.startswith("* "))))
