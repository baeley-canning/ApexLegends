"""show.py -- print listing lines for an address range from a .dis.txt file.

usage: show.py <dis.txt> <start_hex> <end_hex>
"""
import io
import sys

lines = io.open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
lo = int(sys.argv[2], 16)
hi = int(sys.argv[3], 16)
for ln in lines:
    s = ln.strip()
    if not s or not s[0].isdigit():
        if "--" in s or ";" in s:
            continue
        continue
    tok = s.split()[0]
    if len(tok) < 12:
        continue
    try:
        a = int(tok, 16)
    except ValueError:
        continue
    if lo <= a <= hi:
        print(ln)
