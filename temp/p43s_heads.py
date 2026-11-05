"""p43s - dump the object head of every diagonal-consistent base found by p43r."""
import re, sys

SRC = r'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p43q_livedump.txt'
OUT = r'C:\Users\New User\OneDrive\Desktop\cheating\temp\p43s_heads.txt'
PID = 0x1570
SITES = [0x141cd6ef8, 0x147e7a818, 0x350308968, 0x350aa4718, 0x36f6f4818,
         0x36f7b9618, 0x36f7f4728, 0x37982c918, 0x37986b9f8, 0x535b82708]

blocks = {}
cur = None
for l in open(SRC, encoding='utf-8', errors='replace'):
    m = re.match(r'\s+== hit=(0x[0-9a-f]+)', l)
    if m:
        cur = int(m.group(1), 16)
        blocks[cur] = {}
        continue
    m = re.match(r'\s+(0x[0-9a-f]+) rel=([+-]0x[0-9a-f]+) ([0-9a-f]{16})', l)
    if m and cur is not None:
        blocks[cur][int(m.group(2), 16)] = (int(m.group(1), 16), int(m.group(3), 16))

res = []
for hit in SITES:
    by = blocks.get(hit)
    if by is None:
        res.append('hit=%#x MISSING' % hit)
        continue
    b = hit - 0x4c8
    res.append('=' * 78)
    res.append('hit=%#x  base=%#x  (page=%#x off=%#x)  have rel %#x .. %#x' %
               (hit, b, hit & ~0xFFF, hit & 0xFFF, min(by), max(by)))
    res.append('%12s %6s  %s' % ('addr', 'rel', 'value'))
    rel = -0x4c8
    while rel <= 0x80:
        if rel in by:
            a, v = by[rel]
            tag = ''
            if rel == 0:      tag = '  <base type=%d>' % (v & 0xFF)
            if rel == 0x28:   tag = '  <+0x28 dtb?>'
            if rel == 0x440:  tag = '  <pid>'
            if rel == 0x448:  tag = '  <flink>'
            if rel == 0x450:  tag = '  <blink>'
            nm = v.to_bytes(8, 'little')
            asc = ''.join(chr(c) if 32 <= c < 127 else '.' for c in nm)
            res.append('%12x %+6x  %016x  %s%s' % (a, rel, v, asc, tag))
        rel += 8
    res.append('')

open(OUT, 'w', encoding='utf-8').write('\n'.join(res) + '\n')
print('\n'.join(res))
