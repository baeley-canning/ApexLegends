"""p43j - read-only: pull the head window of every hex hit whose pid lane reads
5488 (0x1570) and rate the DirectoryTableBase lane from evidence.

ext\\dumplive.py --hex dumps, per solo hit, [hit-0x4e0..hit-0x480] (object head)
and [hit-0x110..hit+0x40] (pid/name).  base = hit-0x4c8, so the lanes are
Type at -0x4c8, DTB at -0x4a0, pid at -0x088, name at +0x000.  Nothing here
writes; the input is the --hex output of a finished run.
"""
import re
import sys

SRC = r'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p40d_livedump.txt'
OUT = r'C:\Users\New User\OneDrive\Desktop\cheating\temp\p43j_head.txt'
NAME = b'r5apex_dx12'
PID = 0x1570
BASE = 0x4C8
ROW = re.compile(r'^\s+(0x[0-9a-f]+) rel=([+-]0x[0-9a-f]+) ([0-9a-f]{16})')
HIT = re.compile(r'^\s+== hit=(0x[0-9a-f]+)')
RAM_LO, RAM_TOP = 0x1000, None

lines = open(SRC, encoding='utf-8', errors='replace').read().splitlines()
for ln in lines:
    m = re.match(r'PRE ram_top=(0x[0-9a-f]+)', ln)
    if m:
        RAM_TOP = int(m.group(1), 16)
if RAM_TOP is None:
    sys.exit('no PRE ram_top line in %s' % SRC)

blocks, cur = [], None
for ln in lines:
    h = HIT.match(ln)
    if h:
        cur = {'hit': int(h.group(1), 16), 'rows': {}}
        blocks.append(cur)
        continue
    r = ROW.match(ln)
    if r and cur is not None:
        rel = int(r.group(2), 16)
        cur['rows'][rel] = int(r.group(3), 16)

out = []
out.append('blocks=%d ram_top=%#x' % (len(blocks), RAM_TOP))


def lane(b, rel):
    return b['rows'].get(rel, -1)


def frame_ok(v):
    """A DTB frame: low 12 bits clear after masking, inside RAM, not page 0."""
    f = v & 0x000FFFFFFFFFF000
    return 1 if RAM_LO < f < RAM_TOP else 0


pip = 0
out.append('%-12s %-8s %-8s %-18s %-18s %s'
           % ('hit', 'typeA', 'typeB', 'dtbA(-0x4a0)', 'dtbB(-0x580)', 'note'))
hits = []
for b in blocks:
    if lane(b, -0x088) != PID:
        continue
    ta, tb = lane(b, -0x4C8), lane(b, -0x5A8)
    da, db = lane(b, -0x4A0), lane(b, -0x580)
    fa, fb = frame_ok(da), frame_ok(db)
    note = 'A-dtb' if fa else ''
    note += (' ' if note and fb else '') + ('B-dtb' if fb else '')
    note = note.strip() or 'no-dtb'
    out.append('%#012x %#08x %#08x %#018x %#018x %s'
               % (b['hit'], ta & 0xFF, tb & 0xFF, da & (2**64 - 1),
                  db & (2**64 - 1), note))
    hits.append((b, note))

real = [h for h in hits if h[1] != 'no-dtb']
out.append('pid hits=%d with-a-dtb=%d' % (len(hits), len(real)))
for b, note in hits:
    out.append('--- hit=%#x %s' % (b['hit'], note))
    for rel in sorted(b['rows']):
        if rel <= -0x480:
            mark = {0x4C8: ' <-typeA', 0x4A0: ' <-dtbA',
                    0x5A8: ' <-typeB', 0x580: ' <-dtbB'}.get(-rel, '')
            out.append('  rel=%+#06x %016x%s' % (rel, b['rows'][rel], mark))

open(OUT, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print('\n'.join(out[:40]))
print('wrote', OUT)
