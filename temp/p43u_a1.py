"""p43u_a1 - offline census of the p43q dump against the 26200 layout.

The 16-byte pattern `r5apex_dx12.exe\\x00` cannot match a real _EPROCESS on
build 26200: ImageFileName is UCHAR[15] and the name is exactly 15 chars, so
the 16th byte is PriorityClass, not NUL.  This re-reads the dump with the
15-byte pattern, records the byte that follows, and reports how much of the
26200 object the recorded windows actually cover.

Windows of p43q: rel [-0x600,-0x480] and [-0x110,+0x40].  Base = hit-0x338,
so UniqueProcessId (base+0x1d0 = rel -0x168), the DTB lane (rel -0x310) and
the type byte (rel -0x338) sit in the gap *between* the windows; only the
PriorityClass byte at rel +0x0F is always recorded.  The script therefore
labels each field in/cut instead of pretending a missing field is a miss.
Only 8-aligned starts can be rebuilt from qword columns -- say so, do not
silently round.
"""
import re

SRC = r'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p43q_livedump.txt'
OUT = r'C:\Users\New User\OneDrive\Desktop\cheating\temp\p43u_a1.txt'
NAME = b'r5apex_dx12.exe'          # 15 bytes, no NUL
DELTA = 0x338                      # ImageFileName on 26200


def parse():
    blocks = []
    cur = None
    for l in open(SRC, encoding='utf-8', errors='replace'):
        m = re.match(r'\s+== hit=(0x[0-9a-f]+) hit=(\d+)/(\d+)', l)
        if m:
            cur = (int(m.group(1), 16), {})
            blocks.append(cur)
            continue
        m = re.match(r'\s+(0x[0-9a-f]+) rel=([+-]0x[0-9a-f]+) ([0-9a-f]{16})', l)
        if m and cur is not None:
            cur[1][int(m.group(2), 16)] = int(m.group(3), 16)
    return blocks


def q(by, rel):
    return by.get(rel)


def byteat(by, rel):
    v = by.get(rel & ~7)
    return None if v is None else (v >> (8 * (rel & 7))) & 0xFF


def lab(by, rel):
    """recorded qword hex, 'cut' when the offset is outside the windows."""
    v = q(by, rel)
    return 'cut' if v is None else '%016x' % v


blocks = parse()
res = ['blocks=%d  pattern=%r (%d bytes)  base=hit-%#x'
       % (len(blocks), NAME, len(NAME), DELTA), '']

occ = []
for hit, by in blocks:
    if not by:
        continue
    lo, hi = min(by), max(by)
    span = hi - lo + 8 + len(NAME)
    buf = bytearray(span)
    off = -lo
    for rel, v in by.items():
        buf[off + rel:off + rel + 8] = v.to_bytes(8, 'little')
    for rel in range(lo, hi + 1, 8):
        if bytes(buf[off + rel:off + rel + len(NAME)]) == NAME:
            occ.append((hit, rel, by))

res.append('15-byte occurrences in recorded windows: %d' % len(occ))
stored = [o for o in occ if o[1] == 0]
res.append('  at a stored hit (rel=0): %d of %d blocks' % (len(stored), len(blocks)))
other = [o for o in occ if o[1] != 0]
res.append('  at another 8-aligned rel: %d (cannot be found by the 16-byte scan)'
           % len(other))
res.append('')

res.append('%12s %8s %6s %6s %10s %10s %10s %10s %6s' %
           ('hit', 'rel', 'pc@+0f', 'type', 'pid', 'dtb+28', 'token', 'peb', 'score'))
nz = 0
for hit, rel, by in occ:
    pc = byteat(by, rel + 0x0F)
    typ = byteat(by, rel - DELTA)
    if pc and rel == 0:
        nz += 1
    sc = 0
    if pc == 2:
        sc += 4
    elif pc is not None and pc <= 0x20:
        sc += 2
    if typ == 3:
        sc += 2
    dt = q(by, rel - DELTA + 0x28)
    if dt and (dt & 0xFFF) == 0:
        sc += 2
    for ln in (0x1D8, 0x1E0):
        v = q(by, rel - DELTA + ln)
        if v and (v >> 48) == 0xFFFF and (v & 0xFFF) == ln:
            sc += 2
    tk = q(by, rel - DELTA + 0x248)
    if tk and (tk >> 48) == 0xFFFF:
        sc += 2
    pe = q(by, rel - DELTA + 0x2E0)
    if pe and pe < 0x800000000000 and not (pe & 7):
        sc += 2
    res.append('%12x %+#8x %6s %6s %10s %10s %10s %10s %6d' % (
        hit, rel, '--' if pc is None else '%02x' % pc,
        '--' if typ is None else '%02x' % typ,
        lab(by, rel - 0x168), lab(by, rel - DELTA + 0x28),
        lab(by, rel - 0x0F0), lab(by, rel - 0x58), sc))

res.append('')
res.append('stored hits with non-zero byte after the name: %d' % nz)
res.append('stored hits with the name byte-verified: %d' % len(stored))
for hit, rel, by in occ:
    if rel == 0 and byteat(by, rel + 0x0F):
        res.append('  NONZERO hit=%#x pc=%02x row15=%016x'
                   % (hit, byteat(by, rel + 0x0F), q(by, 0x0F)))
nozero = [(h, by) for h, by in blocks if 0 not in by]
res.append('blocks without a rel=0 row: %d' % len(nozero))
for h, by in nozero[:20]:
    res.append('  norow hit=%#x rels=%d lo=%+#x hi=%+#x'
               % (h, len(by), min(by) if by else 0, max(by) if by else 0))
res.append('')
res.append('NOTE qword columns only -> a copy starting mid-qword is invisible here;')
res.append('     coverage of the 26200 head region is the Phase B question, not this.')

open(OUT, 'w', encoding='utf-8').write('\n'.join(res) + '\n')
print('\n'.join(res[:6]))
print('...')
print('\n'.join(res[-5:]))
