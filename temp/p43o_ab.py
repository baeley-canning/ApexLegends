"""p43o - read-only A/B: which lane carries a *physical frame* across all blocks.

Layout A = name at base+0x4C8 (dtb at hit-0x4A0); layout B = name at base+0x5A8
(dtb at hit-0x580).  A DTB is a physical frame below RAM top with a PCID in the
low bits -- it is neither a 0xffff.... kernel VA nor zero.  Counting that shape
over every dumped block decides the geometry without another live run.
"""
import re

SRC = r'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p40d_livedump.txt'
OUT = r'C:\Users\New User\OneDrive\Desktop\cheating\temp\p43o_ab.txt'
RAM_TOP = 0x800000000
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


def frame_like(v):
    """A plausibly real DirectoryTableBase."""
    if not v:
        return False
    frame = v & 0x000FFFFFFFFFF000
    return 0x100000 <= frame < RAM_TOP and (v & 0xFFF) != 0


def zero(v):
    return v == 0


def kva(v):
    return v >> 48 == 0xFFFF


res = ['blocks=%d' % len(blocks), '']
for tag, off in (('A', -0x4A0), ('B', -0x580)):
    vals = [by.get(off) for _, by in blocks]
    have = [v for v in vals if v is not None]
    res.append('layout %s lane %+#x: present=%d frame_like=%d zero=%d kva=%d'
               % (tag, off, len(have), sum(1 for v in have if frame_like(v)),
                  sum(1 for v in have if zero(v)), sum(1 for v in have if kva(v))))
    fl = [(v, h) for v, (h, _) in zip(vals, blocks) if v is not None and frame_like(v)]
    res.append('  sample: ' + ', '.join('%#x@%#x' % (v, h) for v, h in fl[:8]))

# the two winners must also be the *same* blocks, else neither layout is coherent
setA = {h for h, by in blocks if frame_like(by.get(-0x4A0, 0))}
setB = {h for h, by in blocks if frame_like(by.get(-0x580, 0))}
res.append('')
res.append('only A=%d only B=%d both=%d'
           % (len(setA - setB), len(setB - setA), len(setA & setB)))
hits = sorted(x for x in (setA | setB))
res.append('candidate blocks: ' + ', '.join('%#x' % h for h in hits[:20]))
open(OUT, 'w', encoding='utf-8').write('\n'.join(res) + '\n')
print('\n'.join(res))
