"""p43n7 - read-only: rank every hex hit page by KVA density in its head window.

A real _EPROCESS head is dense with 0xffff.... pointers; the stack/string pages
that keep winning the name scan are mostly zeros.  Nothing is changed here, this
only re-reads the finished dump.
"""
import re

SRC = r'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p40d_livedump.txt'
OUT = r'C:\Users\New User\OneDrive\Desktop\cheating\temp\p43n7_density.txt'
ls = open(SRC, encoding='utf-8', errors='replace').read().splitlines()

blocks = []
cur = None
for l in ls:
    m = re.match(r'\s+== hit=(0x[0-9a-f]+)', l)
    if m:
        cur = [int(m.group(1), 16), {}]
        blocks.append(cur)
        continue
    m = re.match(r'\s+0x[0-9a-f]+ rel=([+-]0x[0-9a-f]+) ([0-9a-f]{16})', l)
    if m and cur:
        cur[1][int(m.group(1), 16)] = int(m.group(2), 16)

rank = []
for hit, by in blocks:
    head = [v for o, v in by.items() if -0x600 <= o < -0x480]
    lnk = [v for o, v in by.items() if o in (-0x448, -0x440, -0x528, -0x520)]
    kva = sum(1 for v in head if v >> 48 == 0xFFFF)
    nz = sum(1 for v in head if v)
    lk = sum(1 for v in lnk if v >> 48 == 0xFFFF and (v & 0xFFF) in
             (0x448, 0x450, 0x528, 0x530))
    rank.append((kva, lk, nz, hit, by))
rank.sort(key=lambda r: (-r[0], -r[1]))

res = ['blocks=%d  rank=kva,linkhit,nz,hit' % len(blocks)]
for kva, lk, nz, hit, by in rank[:12]:
    res.append('')
    res.append('kva=%d linkhit=%d nz=%d hit=%#x' % (kva, lk, nz, hit))
    for o in (-0x5A8, -0x580, -0x528, -0x520, -0x4C8, -0x4A0, -0x448, -0x440):
        v = by.get(o)
        if v is None:
            res.append('  %-6s --' % ('%+#x' % o))
        else:
            res.append('  %-6s %016x %s' % ('%+#x' % o, v, '<' if v else ''))
open(OUT, 'w', encoding='utf-8').write('\n'.join(res) + '\n')
print('\n'.join(res[:3]))
