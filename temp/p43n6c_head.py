"""p43n6 - read-only: full head window of the surviving page 0x7edbe5000."""
import re

SRC = r'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p40d_livedump.txt'
OUT = r'C:\Users\New User\OneDrive\Desktop\cheating\temp\p43n6c_accepted.txt'
ls = open(SRC, encoding='utf-8', errors='replace').read().splitlines()
start = next(i for i, l in enumerate(ls) if 'hit=0x312862050' in l)
blk = []
for l in ls[start+1:start+220]:
    m = re.search(r'rel=([+-]0x[0-9a-f]+) ([0-9a-f]{16})', l)
    if not m:
        break
    blk.append((int(m.group(1), 16), m.group(2)))
by = dict(blk)
rows = []
for off in list(range(-0x600, -0x380, 8)):
    v = by.get(off)
    if v is None:
        continue
    be = bytes.fromhex(v)[::-1]
    asc = ''.join(chr(c) if 32 <= c < 127 else '.' for c in be)
    mark = ''
    if off == -0x4C8:
        mark = ' <- A:type,+0x28=dtb(A)'
    if off == -0x4A0:
        mark = ' <- A:dtb = hit-0x4a0'
    if off == -0x5A8:
        mark = ' <- B:type,+0x28=dtb(B)'
    if off == -0x580:
        mark = ' <- B:dtb = hit-0x580'
    if off == -0x448:
        mark = ' <- A:flink'
    if off == -0x440:
        mark = ' <- A:blink'
    if off == -0x528:
        mark = ' <- B:flink'
    rows.append('%+#07x %s %-16s%s' % (off, v, asc, mark))
res = ['hit=0x312862050 rows=%d' % len(rows)] + rows
open(OUT, 'w', encoding='utf-8').write('\n'.join(res) + '\n')
print('\n'.join(res[:3]))


