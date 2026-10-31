"""dm21: dump one initializer function exactly: every rip-relative store in
*address* order with its value resolved, plus NAME markers, so the record
template (and where the name pointer sits inside the record) can be read off
directly.

usage: python dm21.py auto [n]   |   python dm21.py 0x141e55e10 ...
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
dlo, dhi = 0x14e600000, 0x14e740000

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


def show(val, w):
    if val is None:
        return "?"
    if val >= 0xFFFFFFFF00000000:
        return "%d" % (val - (1 << 64))
    if val < 0x10000:
        return "%d" % val
    t = rd(val, 96).split(b"\x00")[0]
    if t and len(t) > 2 and all(32 <= c < 127 for c in t):
        try:
            return '"%s"' % t.decode()
        except UnicodeDecodeError:
            pass
    if val in ident:
        return "name %s" % ident[val]
    s, d = find(val)
    return "%s+%#x" % (s[0], d) if s is not None else "%#x" % val


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


def scan(f0, f1):
    """-> list of (insn_va, dst, width, value, mnemonic) for one function."""
    out = []
    regs = {}
    for ins in md.disasm(rd(f0, f1 - f0), f0):
        if ins.id == 0:
            continue
        mn, ops = ins.mnemonic, ins.operands
        if mn == "lea" and len(ops) == 2 and ops[1].type == X86.X86_OP_MEM \
                and ops[1].mem.base == X86.X86_REG_RIP:
            regs[md.reg_name(ops[0].reg)] = (
                "va", ins.address + ins.size + ops[1].mem.disp)
        elif mn in ("mov", "movabs", "movq", "movd") and len(ops) == 2 \
                and ops[0].type == X86.X86_OP_REG:
            if ops[1].type == X86.X86_OP_IMM:
                regs[md.reg_name(ops[0].reg)] = ("imm", ops[1].imm & (2**64 - 1))
            elif ops[1].type == X86.X86_OP_REG:
                regs[md.reg_name(ops[0].reg)] = regs.get(md.reg_name(ops[1].reg))
            else:
                regs[md.reg_name(ops[0].reg)] = ("zero", 0)
        elif mn in ("xor", "sub") and len(ops) == 2 \
                and ops[0].type == X86.X86_OP_REG and ops[1].type == X86.X86_OP_REG \
                and ops[0].reg == ops[1].reg:
            regs[md.reg_name(ops[0].reg)] = ("zero", 0)
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
            out.append((ins.address, dst, ops[0].size, val, ins.mnemonic))
    return out


args = sys.argv[1:]
if args and args[0] == "auto":
    want = int(args[1]) if len(args) > 1 else 3
    cnt = Counter()
    for m in STORE_RE.finditer(text):
        off = m.end()
        if off + 4 > len(text):
            continue
        dst = tva + off + 4 + struct.unpack_from("<i", text, off)[0]
        if dlo <= dst < dhi:
            i = bisect.bisect_right(fstarts, tva + m.start()) - 1
            if i >= 0 and funcs[i][0] <= tva + m.start() < funcs[i][1]:
                cnt[funcs[i]] += 1
    cand = sorted((f1 - f0, f0, f1, n) for (f0, f1), n in cnt.items()
                  if 3 <= n <= 8)
    targets = [(f0, f1, n) for _sp, f0, f1, n in cand[:want]]
else:
    targets = []
    for a in args:
        v = int(a, 16)
        i = bisect.bisect_right(fstarts, v) - 1
        targets.append((funcs[i][0], funcs[i][1], -1))

for f0, f1, n in targets:
    st = sorted(scan(f0, f1), key=lambda t: t[1])
    p()
    p("## func %#x..%#x  stores=%d  names~%d" % (f0, f1, len(st), n))
    names = [(dst, ident[val]) for _i, dst, _w, val, _m in st
             if val is not None and val in ident and ident[val].startswith("m_")]
    prev = None
    for iva, dst, w, val, mn in st:
        tag = "N>" if any(dst == nd for nd, _nn in names) else "  "
        d = ("   [+%#x]" % (dst - prev)) if prev is not None and dst > prev else ""
        p("  %s %#014x %#014x w=%2d %-6s %-22s%s"
          % (tag, iva, dst, w, mn, show(val, w), d))
        prev = dst
    p("  -- record-relative view (name anchor = each NAME store, +/-0xc0) --")
    p("     %s" % " ".join("%#x" % (dd - names[0][0]) for dd, _n in names))
    # walk from the first name: print each distinct slot offset mod the first
    # observed name gap, plus a raw "offset from record start" listing
    if len(names) >= 2:
        gaps = Counter(b[0] - a[0] for a, b in zip(names, names[1:]))
        p("     name gaps: %s" % gaps.most_common(6))

with open(os.path.join(HERE, "dm21.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
print("dm21.txt: %d lines" % len(lines))
