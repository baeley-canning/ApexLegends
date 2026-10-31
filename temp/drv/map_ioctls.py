"""Map DeviceIoControl call sites in YccDrvv3.dll to IOCTL codes + nearest export.

Outputs map_ioctls.txt
"""
import io
import re

DIS = 'YccDrvv3.dll.dis.txt'
OUT = 'map_ioctls.txt'

line_re = re.compile(r'^\s*(?:0x)?([0-9a-fA-F]{9,})\s{2,}([0-9a-fA-F]{2,})\s{2,}(.*)$')
imm_re = re.compile(r'\b(0xc350[0-9a-fA-F]{4})\b')

lines = io.open(DIS, encoding='utf-8', errors='replace').read().splitlines()

# --- collect exports (name -> rva) from the '--- exports' block
exports = []
inexp = False
exp_re = re.compile(r'^\s*(0x[0-9a-fA-F]+)\s+(.*)$')
for ln in lines:
    if ln.startswith('--- exports'):
        inexp = True
        continue
    if ln.startswith('---') and not ln.startswith('--- exports'):
        inexp = False
        continue
    if inexp:
        m = exp_re.match(ln)
        if m:
            exports.append((int(m.group(1), 16), m.group(2).strip()))
exports.sort()
out = ['exports parsed: %d' % len(exports)]


def owner(rva):
    best = None
    for a, n in exports:
        if a <= rva:
            best = (a, n)
        else:
            break
    return best


# --- walk code lines, find DeviceIoControl call sites
code = []
for i, ln in enumerate(lines):
    m = line_re.match(ln)
    if m:
        code.append((i, int(m.group(1), 16), m.group(3).strip()))

sites = []
for idx, (ln_no, rva, text) in enumerate(code):
    if 'DeviceIoControl' in text and text.startswith('call'):
        code_imm = None
        for back in range(1, 30):
            if idx - back < 0:
                break
            prev = code[idx - back][2]
            pm = imm_re.search(prev)
            if pm:
                code_imm = int(pm.group(1), 16)
                break
            if prev.startswith('ret') or prev.startswith('int3'):
                break
        sites.append((rva, code_imm, ln_no))

out.append('DeviceIoControl call sites: %d' % len(sites))
out.append('')
for rva, c, ln_no in sites:
    own = owner(rva)
    out.append('site 0x%X code=%s owner=%s' % (
        rva,
        ('0x%X' % c) if c else '?',
        ('0x%X %s' % own) if own else '?'))
    for back in range(18, 0, -1):
        j = ln_no - back
        if j >= 0:
            out.append('    ' + lines[j].strip())

io.open(OUT, 'w', encoding='utf-8').write('\n'.join(out))
print('\n'.join(out[:6]))
