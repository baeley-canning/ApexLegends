"""dis32.py -- linear disassembly of one .pdata function with call/lea targets
annotated.  Usage: python dis32.py 0x141934270 [--all]"""
import sys

import capstone

import dm32

IMM = capstone.x86.X86_OP_IMM
MEM = capstone.x86.X86_OP_MEM
RIP = capstone.x86.X86_REG_RIP

lo = int(sys.argv[1], 16)
f = dm32.func_at(lo)
if not f:
    sys.exit("not a function")
s = dm32.sec_of(f[0])
blob = dm32.raw[s[4] + (f[0] - s[1]):s[4] + (f[1] - s[1])]
insns = list(dm32.md.disasm(blob, f[0]))
print("%#x-%#x  %d insn" % (f[0], f[1], len(insns)))
for ins in insns:
    note = ""
    ops = ins.operands
    if ins.mnemonic in ("call", "jmp") and ops and ops[0].type == IMM:
        note = "   %s" % dm32.secname(ops[0].imm)
    elif ins.mnemonic == "lea" and len(ops) == 2 and ops[1].type == MEM \
            and ops[1].mem.base == RIP:
        tgt = ins.address + ins.size + ops[1].mem.disp
        nm = dm32.string_at(tgt)
        note = "   %#x %s" % (tgt, "(%r)" % nm if nm else
                              dm32.secname(tgt))
    print("%#012x  %-8s %-42s%s"
          % (ins.address, ins.mnemonic, ins.op_str, note))

