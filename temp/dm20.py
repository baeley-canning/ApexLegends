"""dm20: fold test.  For every store we know (instruction-confirmed, with the
owning function) find the nearest name store in the same function and compute
d = dst - name_dst.  Then, for a list of candidate strides S, fold d mod S and
see which S makes all stores land on a handful of residues.  A true stride
collapses the whole function onto a fixed template; a wrong one smears.

Also prints the wide d histogram (name-0x100 .. name+0x100) so slots at
+0x44 / +0x4c (i.e. -0x24 / -0x1c under a 0x68 stride) can be recognised as
the same slot or as different ones.

usage: python dm20.py [lo-hi]
"""
import bisect
import os
import pickle
import re
import struct
import sys
from collections import Counter

import capstone

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "dm11_cache.pkl")
lo_s = sys.argv[1] if len(sys.argv) > 1 else "0x14e600000-0x14e740000"
dlo, dhi = (int(x, 16) for x in lo_s.split("-"))
WIDE = 0x100
CAND = (0x30, 0x38, 0x40, 0x48, 0x50, 0x58, 0x60, 0x68, 0x70, 0x78, 0x80, 0xA0)

lines = []


def p(s=""):
    lines.append(s)


with open(CACHE, "rb") as fh:
    C = pickle.load(fh)
funcs, ident, secs = C["funcs"], C["ident"], C["secs"]
fstarts = [f[0] for f in funcs]
data = open(PATH, "rb").read()


def find(va):
    for s in secs:
        if s[1] <= va < s[1] + max(s[2], s[3]):
            return s, va - s[1]
    return None, None


def rd(va, n):
    s, d = find(va)
    if s is None or d >= s[3]:
        return b"\x00" * n
    return data[s[4] + d:s[4] + d + n]


def func_of(va):
    i = bisect.bisect_right(fstarts, va) - 1
    if i >= 0 and funcs[i][0] <= va < funcs[i][1]:
        return funcs[i]
    return None


ts = next(s for s in secs if s[5] & 0x20)
text = data[ts[4]:ts[4] + ts[3]]
tva = ts[1]

md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = True
md.skipdata = True
X86 = capstone.x86

MODRM = rb"[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]"
PFX = rb"(?:\x66|\xF3|\xF2|\x48|\x49|\x4C|\x4D|)"
STORE_RE = re.compile(
    rb"(?:" + PFX + rb"\x0F(?:\x11|\x7F)|" + PFX + rb"(?:\x88|\x89|\xC6|\xC7))"
    + MODRM)

pre = []
for m in STORE_RE.finditer(text):
    off = m.end()
    if off + 4 > len(text):
        continue
    dst = tva + off + 4 + struct.unpack_from("<i", text, off)[0]
    if dlo <= dst < dhi:
        pre.append(tva + m.start())

md1 = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md1.detail = True
raw, seen, owners = [], set(), set()
for iva in pre:
    for ins in md1.disasm(text[iva - tva:iva - tva + 16], iva):
        ops = ins.operands
        if ops and ops[0].type == X86.X86_OP_MEM \
                and ops[0].mem.base == X86.X86_REG_RIP:
            dst = ins.address + ins.size + ops[0].mem.disp
            if (ins.address, dst) not in seen:
                seen.add((ins.address, dst))
                raw.append((ins.address, dst, ops[0].size))
                f = func_of(ins.address)
                if f:
                    owners.add(f)
        break
p("## confirmed stores %d in %d functions" % (len(raw), len(owners)))

stores = {}
for f0, f1 in sorted(owners):
    regs = {}
    for ins in md.disasm(rd(f0, f1 - f0), f0):
        if ins.id == 0:
            continue
        mn, ops = ins.mnemonic, ins.operands
        if mn == "lea" and len(ops) == 2 and ops[1].type == X86.X86_OP_MEM \
                and ops[1].mem.base == X86.X86_REG_RIP:
            regs[md.reg_name(ops[0].reg)] = (
                "va", ins.address + ins.size + ops[1].mem.disp)
        elif mn in ("mov", "movabs") and len(ops) == 2 \
                and ops[0].type == X86.X86_OP_REG:
            if ops[1].type == X86.X86_OP_IMM:
                regs[md.reg_name(ops[0].reg)] = ("imm", ops[1].imm & (2**64 - 1))
            elif ops[1].type == X86.X86_OP_REG:
                regs[md.reg_name(ops[0].reg)] = regs.get(md.reg_name(ops[1].reg))
            else:
                regs[md.reg_name(ops[0].reg)] = None
        elif ops and ops[0].type == X86.X86_OP_REG:
            regs[md.reg_name(ops[0].reg)] = None
        if ops and ops[0].type == X86.X86_OP_MEM \
                and ops[0].mem.base == X86.X86_REG_RIP:
            dst = ins.address + ins.size + ops[0].mem.disp
            val = None
            if len(ops) == 2:
                if ops[1].type == X86.X86_OP_IMM:
                    val = ops[1].imm & (2**64 - 1)
                elif ops[1].type == X86.X86_OP_REG:
                    got = regs.get(md.reg_name(ops[1].reg))
                    if got:
                        val = got[1]
            stores[(ins.address, dst)] = (ops[0].size, val, f0)

names = []
for (iva, dst), (_w, val, f) in stores.items():
    if val is not None and val in ident and ident[val].startswith("m_"):
        names.append((dst, ident[val], f))
names.sort()
p("## m_* name stores %d" % len(names))

by_f = Counter(f for _d, _n, f in names)
top = [f for f, _n in by_f.most_common(4)]

pool = [(dst, w, val, f) for (iva, dst), (w, val, f) in stores.items()]

wide = Counter()
pairs = []                                   # fold input, d values
for f in top:
    fn = sorted((d for d, _n, ff in names if ff == f))
    for dst, w, val, ff in pool:
        if ff != f:
            continue
        i = bisect.bisect_left(fn, dst)
        best = None
        for j in (i - 1, i):
            if 0 <= j < len(fn) and abs(fn[j] - dst) <= WIDE * 4:
                if best is None or abs(fn[j] - dst) < abs(best - dst):
                    best = fn[j]
        if best is None:
            continue
        d = dst - best
        if -WIDE <= d <= WIDE:
            wide[d] += 1
        pairs.append(d)

p()
p("## wide histogram (store_dst - nearest_name_dst), top 4 functions")
for d in sorted(wide):
    if wide[d] >= 8:
        p("   %+#06x %5d  %s" % (d, wide[d], "." * min(60, wide[d] // 20)))

p()
p("## fold test: residues of d mod S  (good S -> few residues cover all)")
for S in CAND:
    h = Counter(d % S for d in pairs)
    covered = sum(n for _r, n in h.most_common(12))
    p("   S=%#05x residues=%3d  top12=%.1f%%  top: %s"
      % (S, len(h), 100.0 * covered / max(1, len(pairs)),
         " ".join("%#x:%d" % kv for kv in h.most_common(8))))

with open(os.path.join(HERE, "dm20.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
print("dm20.txt: %d lines" % len(lines))
