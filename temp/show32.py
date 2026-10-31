"""show32.py -- print the dm32.txt block of one class (all rows)."""
import sys
import os

HERE = os.path.dirname(os.path.abspath(__file__))
want = sys.argv[1]
lines = open(os.path.join(HERE, "dm32.txt")).read().splitlines()
out = []
on = False
for ln in lines:
    if ln.startswith("### "):
        on = ln.split()[1] == want
    if on:
        out.append(ln)
print("\n".join(out))
