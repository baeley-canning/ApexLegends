"""dm28: reconstruct the record template *exactly* from the initializer stores.

dm27 showed every store in a datamap initializer is a RIP-relative absolute
address (`mov qword ptr [rip+k], imm`), so the target address of each store is
known without any base guesswork.  This walks those stores, decodes the value
(string / .text func / .data ptr / int), groups them into 0x68 slots and prints
the resulting per-record template plus the record boundaries.  That settles
which displacement holds fieldName / fieldOffset / fieldSize.

Usage: python dm28.py
Output: temp/dm28.txt
"""
import os
import struct

import capstone
import pefile

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
IMGBASE = 0x140000000
FUNCS = [0x1418d8d60, 0x1420d8e70, 0x142121bd0]

pe = pefile.PE(PATH, fast_load=True)
raw = open(PATH, "rb").read()
secs = [(s.Name.rstrip(b"\x00").decode("latin1"), IMGBASE + s.VirtualAddress,
         s.Misc_VirtualSize, s.SizeOfRawData, s.PointerToRawData)
        for s in pe.sections]


def sec_of(va):
    for s in secs:
        if s[1] <= va < s[1] + max(s[2], s[3]):
            return s
    return None


def off(va):
    s = sec_of(va)
    return None if s is None else s[4] + (va - s[1])


def cstr(va, n=64):
    o = off(va)
    if o is None:
        return None
    e = raw.find(b"\x00", o, o + n)
    if e < 0:
        return None
    try:
        s = raw[o:e].decode("ascii")
    except UnicodeDecodeError:
        return None
    return s if s and all(32 <= ord(c) < 127 for c in s) else None


def describe(v):
    """decode a stored 64-bit value into something readable"""
    if v == 0:
        return "0"
    if v < 0x100000000:
        if v == 0xffffffff:
            return "-1(i32)"
        return "%#x" % v
    s = sec_of(v)
    if s is None:
        return "%#x ?" % v
    if s[0] == ".rdata":
        t = cstr(v)
        if t:
            return "'%s'" % t
        return "%#x .rdata+%#x" % (v, v - s[1])
    return "%#x %s+%#x" % (v, s[0], v - s[1])


md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = True
out = []


def p(s=""):
    out.append(s)
    print(s)


WIDTH = {"byte": 1, "word": 2, "dword": 4, "qword": 8, "xmmword": 16}


def run(fn):
    o = off(fn)
    code = raw[o:o + 0x2000]
    const = {}          # reg -> (value, kind)  kind: 'lea'|'imm'
    stores = []         # (target, width, text_of_value, ins_addr)
    n = 0
    for ins in md.disasm(code, fn):
        n += 1
        if n > 1200:
            break
        ops = ins.operands
        # constant propagation (lea / mov imm)
        if ins.mnemonic == "lea" and len(ops) == 2 and \
                ops[0].type == capstone.x86.X86_OP_REG:
            m = ops[1].mem
            if m.base == capstone.x86.X86_REG_RIP:
                const[ops[0].reg] = (ins.address + ins.size + m.disp, "lea")
            elif m.base in const and not m.index:
                const[ops[0].reg] = (const[m.base][0] + m.disp, "lea")
            else:
                const.pop(ops[0].reg, None)
        elif ins.mnemonic in ("mov", "movabs") and len(ops) == 2 and \
                ops[0].type == capstone.x86.X86_OP_REG:
            if ops[1].type == capstone.x86.X86_OP_IMM:
                const[ops[0].reg] = (ops[1].imm & 0xffffffffffffffff, "imm")
            elif ops[1].type == capstone.x86.X86_OP_MEM:
                const.pop(ops[0].reg, None)
        elif ins.mnemonic in ("xor", "sub") and len(ops) == 2 and \
                ops[0].type == capstone.x86.X86_OP_REG and \
                ops[1].type == capstone.x86.X86_OP_REG and \
                ops[0].reg == ops[1].reg:
            const[ops[0].reg] = (0, "imm")
        # stores to absolute (rip-relative) memory
        if len(ops) == 2 and ops[0].type == capstone.x86.X86_OP_MEM and \
                ops[0].mem.base == capstone.x86.X86_REG_RIP and \
                ins.mnemonic.startswith(("mov", "vmov")):
            tgt = ins.address + ins.size + ops[0].mem.disp
            w = WIDTH.get(ins.op_str.split(" ptr")[0], 0)
            if ops[1].type == capstone.x86.X86_OP_REG:
                v, k = const.get(ops[1].reg, (None, None))
                if v is None:
                    desc = ins.reg_name(ops[1].reg)
                    if ops[1].reg == capstone.x86.X86_REG_XMM0:
                        desc = "xmm0(zeros)"
                    stores.append((tgt, w, desc, ins.address))
                    continue
                if k == "imm":
                    desc = describe(v) if v > 0xffffffff else "%#x" % v
                else:
                    desc = describe(v)
            elif ops[1].type == capstone.x86.X86_OP_IMM:
                desc = describe(ops[1].imm & 0xffffffffffffffff)
            else:
                desc = ins.op_str
            stores.append((tgt, w, desc, ins.address))
    return stores, n


for fn in FUNCS:
    stores, n = run(fn)
    p("=" * 90)
    p("### %#x   (%d insns, %d abs stores)" % (fn, n, len(stores)))
    p("=" * 90)
    if not stores:
        continue
    # cluster the targets: datamap arrays are contiguous, convars/cold data are far away
    tgts = sorted(stores)
    groups = []
    cur = [tgts[0]]
    for s in tgts[1:]:
        if s[0] - cur[-1][0] > 0x100:
            groups.append(cur)
            cur = [s]
        else:
            cur.append(s)
    groups.append(cur)
    p("## %d clusters" % len(groups))
    for g in groups:
        lo, hi = g[0][0], g[-1][0]
        p("   %#x .. %#x  span %#x  n=%d" % (lo, hi, hi - lo, len(g)))
    p("")
    for g in groups:
        if len(g) < 12:
            continue
        lo = g[0][0]
        p("-" * 90)
        p("## cluster %#x .. %#x   n=%d" % (lo, g[-1][0], len(g)))
        p("## delta from %#x, shown with delta%%0x68 in [ ]" % lo)
        prev = 0
        for tgt, w, desc, ia in g:
            d = tgt - lo
            p("   +0x%05x [%#04x] w%-2d %-32s (%#x)" % (d, d % 0x68, w, desc, ia))
        p("")
        # stride evidence: distinct deltas modulo stride
        for stride in (0x68, 0x70, 0x78, 0x80):
            print("   stride %#x: %d/%d hit" % (
                stride, len({d % stride for d in
                             (s[0] - lo for s in g)}), len(g)))

with open(os.path.join(HERE, "dm28.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
p("")
p("wrote dm28.txt (%d lines)" % len(out))

