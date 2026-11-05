"""p43v_blk - print one dumped block (rows between two `== hit=` lines)."""
import sys

SRC = r'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p43v_livedump.txt'
want = sys.argv[1].lower()
on = False
rows = 0
for l in open(SRC, encoding='utf-8', errors='replace'):
    if l.startswith('  == hit='):
        on = want in l
        if on:
            print(l.rstrip())
        continue
    if on:
        print(l.rstrip())
        rows += 1
        if rows > int(sys.argv[2] if len(sys.argv) > 2 else 130):
            break
