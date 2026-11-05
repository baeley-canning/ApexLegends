"""p43p - read-only: locate the *pid* dword around every name hit.

The name hit is 15 unique chars, so the true _EPROCESS page is somewhere in the
142 blocks -- the pid gate rejecting all but one means PID_OFFS is wrong, not
that the page is missing.  A pid is a rare dword, so the offset where 0x1570
actually sits next to the name gives the true UniqueProcessId delta and, with
it, the base and the DirectoryTableBase lane.
"""
import re

SRC = r'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p40d_livedump.txt'
OUT = r'C:\Users\New User\OneDrive\Desktop\cheating\temp\p43p_pid.txt'
PID = 0x1570
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

res = ['blocks=%d pid=%#x (dword, high dword 0)' % (len(blocks), PID), '']
found = 0
for hit, by in blocks:
    lanes = []
    for rel, v in sorted(by.items()):
        # dump prints the qword as %016x, i.e. reversed w.r.t. memory: the byte at
        # `rel` is the *top* byte of the qword.
        if (v >> 32) & 0xFFFFFFFF == PID:
            lanes.append(rel)
        if v & 0xFFFFFFFF == PID:
            lanes.append(rel + 4)
    if not lanes:
        continue
    found += 1
    base = hit + lanes[0] - 0x440
    dtb = by.get(lanes[0] - 0x418)
    res.append('hit=%#x pid_rel=%s base_if_0440=%#x dtb=%s'
               % (hit, ','.join('%+#x' % x for x in lanes), base,
                  '-' if dtb is None else '%016x' % dtb))
res.append('')
res.append('blocks with a pid dword: %d/%d' % (found, len(blocks)))
open(OUT, 'w', encoding='utf-8').write('\n'.join(res) + '\n')
print('\n'.join(res[:4]))
