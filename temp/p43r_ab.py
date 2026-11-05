"""p43r - offline census of the p43q live dump: every pid hit -> every base it
implies, and what that base actually looks like.

p43q's gate accepted exactly two candidates and both walked nowhere, so the
question is not "is the geometry right" but "which bases did the pid point at,
and did the dump even contain the bytes needed to judge them".  This reads the
dump only (no device), so it is safe to run repeatedly.

For each `r5apex_dx12.exe` pid hit the script walks PID_OFFS back to a base,
then prints type byte / +0x28 frame / link lane / the name at +0x4c8 for both
name layouts (-0x4c8 and -0x580).  A real base must show: name == the string,
type byte small, flink a kernel VA.  Anything else is a pid-shaped coincidence.
"""
import re

SRC = r'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p43q_livedump.txt'
OUT = r'C:\Users\New User\OneDrive\Desktop\cheating\temp\p43r_ab.txt'
PID = 0x1570
MASK = 0x000FFFFFFFFFF000
RAM_TOP = 0x800000000
NAME = b'r5apex_dx12.exe\x00'
PID_OFFS = range(0x410, 0x4A0, 4)
NAME_DELTAS = range(-0x680, -0x4c0, 8)

blocks = []
cur = None
for l in open(SRC, encoding='utf-8', errors='replace'):
    m = re.match(r'\s+== hit=(0x[0-9a-f]+)', l)
    if m:
        cur = [int(m.group(1), 16), {}]
        blocks.append(cur)
        continue
    m = re.match(r'\s+(0x[0-9a-f]+) rel=([+-]0x[0-9a-f]+) ([0-9a-f]{16})', l)
    if m and cur is not None:
        cur[1][int(m.group(2), 16)] = (int(m.group(1), 16), int(m.group(3), 16))


def q(by, rel):
    return by.get(rel, (0, 0))[1]


def frame(v):
    return v & MASK


def frame_ok(v):
    f = frame(v)
    return 0x100000 <= f < RAM_TOP and (v & 0xFFF) != 0


def kva(v):
    return (v >> 48) == 0xFFFF and (v & 0xFFF) == 0


res = ['blocks=%d  pid=%#x' % (len(blocks), PID), '']
pid_hits = []
for hit, by in blocks:
    for rel, (addr, v) in sorted(by.items()):
        if (v & 0xFFFFFFFF) == PID and (v >> 32) == 0:
            pid_hits.append((hit, rel, addr))

res.append('pid hits: %d' % len(pid_hits))
bases = {}
for hit, rel, addr in pid_hits:
    for o in PID_OFFS:
        b = addr - o
        d = b - hit
        if d in NAME_DELTAS:
            bases.setdefault((hit, d, o), 0)
            bases[(hit, d, o)] += 1

res.append('distinct (hit, delta, pid@) triples: %d' % len(bases))
if not bases:
    res.append('NO BASE: no pid hit sits inside the PID_OFFS window of a NAME_DELTA')
res.append('')
res.append('%12s %8s %7s %6s %12s %12s %8s %10s' %
           ('hit', 'delta', 'pid@', 'type', '+0x28', '+0x448', 'pidx', 'flink-kva'))
for (hit, d, o), n in sorted(bases.items()):
    by = dict(blocks[[h for h, _ in blocks].index(hit)][1])
    dtb = q(by, d + 0x28)
    fl = q(by, d + 0x448)
    typ = q(by, d) & 0xFF
    lo = min(by) if by else 0
    nmrel, nmsrel = d + 0x4c8, d + 0x580
    nm = q(by, nmrel) if nmrel in by else 0
    nms = q(by, nmsrel) if nmsrel in by else 0
    res.append('%#12x %#8x %#7x %6d %12s %12s %8s %10s  name4c8=%s name580=%s' % (
        hit, d, o, typ, ('%#x' % dtb) if frame_ok(dtb) else '-',
        ('%#x' % fl) if kva(fl) else '-',
        n, 'yes' if kva(fl) else 'no',
        'in' if d in by else 'cut', 'in' if nmrel in by else 'cut'))
    res.append('%14s name8_4c8=%016x name8_580=%016x' % ('', nm, nms))

res.append('')
res.append('name string present: %d blocks contain %r' %
           (sum(1 for _, by in blocks if any(v == int.from_bytes(NAME[:8], 'little')
                                             for _, v in by.values())), NAME[:8]))

# what the gate actually walked
walked = []
for (hit, d, o), _ in sorted(bases.items()):
    dtb = q(dict(blocks[[h for h, _ in blocks].index(hit)][1]), d + 0x28)
    if frame_ok(dtb):
        walked.append((hit, d, dtb))
res.append('frame-shaped candidates the gate can walk: %d' %
           len(walked))
for hit, d, dtb in walked:
    res.append('  hit=%#x base=%#x dtb=%#x' % (hit, hit + d, dtb))

open(OUT, 'w', encoding='utf-8').write('\n'.join(res) + '\n')
print('\n'.join(res))
