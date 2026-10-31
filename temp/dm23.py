"""dm23: annotated linear disassembly of one initializer function.  Every
instruction is printed; rip-relative operands are resolved to a value/string so
the record template can be read straight off the code.

usage: python dm23.py 0x1418d8d60 [0x141e55600 ...]
"""
import bisect
import os
import pickle
import struct
import sys

import capstone

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "dm11_cache.pkl")
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


def desc(va):
    """-> short annotation for a pointer/scalar"""
    if va is None:
        return "?"
    t = rd(va, 96).split(b"\x00")[0]
    if len(t) >= 3 and all(32 <= c < 127 for c in t):
        try:
            return "'%s'" % t.decode()
        except UnicodeDecodeError:
            pass
    if va in ident:
        return "name " + ident[va]
    if va < 0x100000:
        return "=%d" % va
    s, d = find(va)
    return "%s+%#x" % (s[0], d) if s is not None else "%#x" % va


md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = True
X86 = capstone.x86

tvec = None
for a in sys.argv[1:]:
    v = int(a, 16)
    i = bisect.bisect_right(fstarts, v) - 1
    f0, f1 = funcs[i][0], funcs[i][1]
    p()
    p("=" * 78)
    p("## function %#x .. %#x  (%d bytes)" % (f0, f1, f1 - f0))
    regs = {}
    for ins in md.disasm(rd(f0, f1 - f0), f0):
        if ins.id == 0:
            continue
        note = ""
        # track & resolve
        ops = ins.operands
        if ins.mnemonic == "lea" and len(ops) == 2 \
                and ops[1].type == X86.X86_OP_MEM \
                and ops[1].mem.base == X86.X86_REG_RIP:
            tgt = ins.address + ins.size + ops[1].mem.disp
            regs[md.reg_name(ops[0].reg)] = ("va", tgt)
            note = "   ; %s = %s" % (md.reg_name(ops[0].reg), desc(tgt))
        elif ins.mnemonic in ("mov", "movabs") and len(ops) == 2 \
                and ops[0].type == X86.X86_OP_REG:
            if ops[1].type == X86.X86_OP_IMM:
                regs[md.reg_name(ops[0].reg)] = ("imm", ops[1].imm & (2**64 - 1))
                note = "   ; %s = %#x" % (md.reg_name(ops[0].reg),
                                          ops[1].imm & (2**64 - 1))
            else:
                got = regs.get(md.reg_name(ops[1].reg)) \
                    if ops[1].type == X86.X86_OP_REG else None
                regs[md.reg_name(ops[0].reg)] = got
                if got:
                    note = "   ; %s = %s" % (md.reg_name(ops[0].reg),
                                              desc(got[1]))
        elif ins.mnemonic in ("pxor", "xorps", "xorpd", "xor", "sub") \
                and len(ops) == 2 and ops[0].type == X86.X86_OP_REG \
                and ops[1].type == X86.X86_OP_REG and ops[0].reg == ops[1].reg:
            regs[md.reg_name(ops[0].reg)] = ("imm", 0)
            note = "   ; zero"
        for k, o in enumerate(ops):
            if o.type == X86.X86_OP_MEM and o.mem.base == X86.X86_REG_RIP:
                tgt = ins.address + ins.size + o.mem.disp
                s, d = find(tgt)
                loc = "%s+%#x" % (s[0], d) if s is not None else "%#x" % tgt
                note += "   ; [%s]" % loc
                if k == 0 and len(ops) == 2:
                    got = None
                    if ops[1].type == X86.X86_OP_IMM:
                        got = ("imm", ops[1].imm & (2**64 - 1))
                    elif ops[1].type == X86.X86_OP_REG:
                        got = regs.get(md.reg_name(ops[1].reg))
                    if got:
                        note += " <= " + desc(got[1])
                    else:
                        note += " <= %s" % (
                            md.reg_name(ops[1].reg)
                            if ops[1].type == X86.X86_OP_REG else "?")
                elif k == 1:
                    # memory read: show what the pointer points at
                    cur = struct.unpack("<Q", rd(tgt, 8))[0]
                    if cur:
                        note += " (now %s)" % desc(cur)
        p("   %#014x  %-46s%s"
          % (ins.address, "%s %s" % (ins.mnemonic, ins.op_str), note))

with open(os.path.join(HERE, "dm23.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
print("dm23.txt: %d lines" % len(lines))
