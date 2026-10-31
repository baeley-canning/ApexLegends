"""find_xref.py -- print context for every reference to one or more RVAs.

usage:  python find_xref.py <driver.sys> <rva> [rva ...] [--before N] [--after N]

A reference is any instruction with a rip-relative memory operand or an
immediate operand that resolves to one of the given RVAs.  Used to walk
KMDF driver chains: DriverEntry -> EvtDriverDeviceAdd -> queue config ->
EvtIoDeviceControl.
"""
import io
import os
import sys

import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64
from capstone.x86 import X86_OP_IMM, X86_OP_MEM, X86_REG_RIP

DRV = os.path.join(os.environ["SystemRoot"], "System32", "drivers")


def main():
    args = [a for a in sys.argv[1:]]
    before, after = 8, 22
    if "--before" in args:
        i = args.index("--before")
        before = int(args[i + 1], 0)
        del args[i:i + 2]
    if "--after" in args:
        i = args.index("--after")
        after = int(args[i + 1], 0)
        del args[i:i + 2]
    name, targets = args[0], [int(a, 0) for a in args[1:]]
    path = name if os.path.isabs(name) else os.path.join(DRV, name)
    pe = pefile.PE(path, fast_load=False)
    base = pe.OPTIONAL_HEADER.ImageBase
    buf = open(path, "rb").read()

    out = ["; %s  imagebase=%#x  targets=%s"
           % (os.path.basename(path), base, ", ".join("%#x" % t for t in targets))]
    md = Cs(CS_ARCH_X86, CS_MODE_64)
    md.detail = True
    want, n = set(targets), 0
    for s in pe.sections:
        if not (s.Characteristics & 0x20000000):
            continue
        code = buf[s.PointerToRawData:s.PointerToRawData + s.SizeOfRawData]
        insns = list(md.disasm(code, s.VirtualAddress))
        for idx, ins in enumerate(insns):
            hit = False
            for op in ins.operands:
                if op.type == X86_OP_MEM and op.mem.base == X86_REG_RIP:
                    if ins.address + ins.size + op.mem.disp in want:
                        hit = True
                elif op.type == X86_OP_IMM and (op.imm - base) in want:
                    hit = True
            if not hit:
                continue
            n += 1
            out.append("; ---- xref @ %#x ----" % ins.address)
            for j in range(max(0, idx - before), min(len(insns), idx + after + 1)):
                k = insns[j]
                out.append("%s%08x  %-16s %-7s %s"
                           % ("> " if j == idx else "  ", k.address, k.bytes.hex(),
                              k.mnemonic, k.op_str))
            out.append("")
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "xref.txt")
    io.open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("wrote %s (%d refs)" % (dst, n))


main()
