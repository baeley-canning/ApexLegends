"""p43t - invariant scan: find any offset in the dumped windows that looks like an
_EPROCESS base (dispatcher type, page-aligned frame at +0x28, pid at +0x440, name
at +0x4c8 or +0x5a8), independent of the NAME_DELTAS assumption.

prints every block's best hit with the offsets it used, so a wrong delta shows up
as "pid/name in the wrong place" instead of a silent zero.
"""
import re

SRC = r'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p43q_livedump.txt'
OUT = r'C:\Users\New User\OneDrive\Desktop\cheating\temp\p43t_scan.txt'
PID = 0x1570
NAME8 = b'r5apex_d'
RAM_TOP = 0x800000000
TYPES = {0x03, 0x07}

NAME16 = b'r5apex_dx12.exe\x00'
RAM_TOP = 0x800000000

blocks = []
cur = None
for l in open(SRC, encoding='utf-8', errors='replace'):
    m = re.match(r'\s+== hit=(0x[0-9a-f]+)', l)
    if m:
        cur = (int(m.group(1), 16), {})
        blocks.append(cur)
        continue
    m = re.match(r'\s+(0x[0-9a-f]+) rel=([+-]0x[0-9a-f]+) ([0-9a-f]{16})', l)
    if m and cur is not None:
        cur[1][int(m.group(2), 16)] = (int(m.group(1), 16), int(m.group(3), 16))


def name_at(by, rel, off, aligned):
    q0 = by.get(rel + off, None)
    q1 = by.get(rel + off + 8, None)
    if q0 is None or q1 is None:
        return None
    if aligned:
        b = q0[1].to_bytes(8, 'little') + q1[1].to_bytes(8, 'little')
    else:
        b = (q0[1] >> 32).to_bytes(4, 'little') + q1[1].to_bytes(8, 'little')
        b += (by.get(rel + off + 0x10, (0, 0))[1] & 0xFFFFFFFF).to_bytes(4, 'little')
    return b


res = ['blocks=%d' % len(blocks), '']
for hit, by in blocks:
    lo, hi = min(by), max(by)
    rows = []
    for rel in sorted(by):
        addr, v = by[rel]
        # pid may sit at base+0x440 (aligned) or base+0x444 (high dword)
        cands = []
        if (v & 0xFFFFFFFF) == PID and (v >> 32) == 0:
            cands.append(rel - 0x440)
        if (v >> 32) == PID:
            cands.append(rel - 0x444)
        for br in cands:
            if br not in by:
                continue
            typ = by[br][1] & 0xFF
            dtbv = by.get(br + 0x28, (0, 0))[1]
            frame = dtbv & 0x000FFFFFFFFFF000
            ok_frame = (dtbv & 0xFFF) == 0 and 0x100000 <= frame < RAM_TOP
            okn = []
            for off, al in ((0x4c8, True), (0x4c4, False), (0x5a8, True), (0x5a4, False)):
                nm = name_at(by, br, off, al)
                if nm == NAME16:
                    okn.append('%#x' % off)
            rows.append((br, typ, ok_frame, okn, dtbv))
    res.append('hit=%#x have %#x..%#x  pid-sites=%d' % (hit, lo, hi, len(rows)))
    for br, typ, okf, okn, dtbv in rows:
        res.append('   base=%#x rel=%+#06x type=%#x frame=%s dtb=%#x name=%s%s'
                   % (by[br][0], br, typ, 'ok' if okf else 'BAD', dtbv,
                      ','.join(okn) or '-',
                      '  <<< FULL MATCH' if okf and okn else ''))

open(OUT, 'w', encoding='utf-8').write('\n'.join(res) + '\n')
full = [l for l in res if '<<<' in l]
print('\n'.join(full) if full else 'no full match')
print('lines=%d' % len(res))
