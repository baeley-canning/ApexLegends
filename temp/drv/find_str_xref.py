"""find_str_xref.py -- find code that references a string, print context.

usage:  python find_str_xref.py <driver.sys> <substring> [before] [after]

Finds the RVA of the first UTF-16LE and ASCII occurrence of <substring>
in the image, then prints every `lea reg, [rip + disp]` (and
`mov reg, imm64`) whose target equals that RVA, with context, so KMDF
entry paths (WdfDeviceInitAssignName / WdfDeviceCreateSymbolicLink ...)
can be located and the surrounding callbacks dumped.
"""
import io
import os
import sys

import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64
from capstone.x86 import X86_OP_IMM, X86_OP_MEM, X86_REG_RIP

DRV = os.path.join(os.environ["SystemRoot"], "System32", "drivers")


def main():
    name, needle = sys.argv[1], sys.argv[2]
    before = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    after = int(sys.argv[4]) if len(sys.argv) > 4 else 16
    path = name if os.path.isabs(name) else os.path.join(DRV, name)
    pe = pefile.PE(path, fast_load=False)
    base = pe.OPTIONAL_HEADER.ImageBase
    buf = open(path, "rb").read()

    def off2rva(off):
        for s in pe.sections:
            lo, hi = s.PointerToRawData, s.PointerToRawData + s.SizeOfRawData
            if lo <= off < hi:
                return s.VirtualAddress + (off - lo)
        return None

    targets = []
    for enc, label in (("utf-16-le", "w"), ("latin-1", "a")):
        pos = buf.find(needle.encode(enc))
        if pos >= 0:
            rva = off2rva(pos)
            if rva is not None:
                targets.append((rva, "%s %r @ rva %#x" % (label, needle, rva)))
    out = ["; %s  imagebase=%#x  refs -> %s"
           % (os.path.basename(path), base, "; ".join(t[1] for t in targets) or "none")]

    md = Cs(CS_ARCH_X86, CS_MODE_64)
    md.detail = True
    want = set(t[0] for t in targets)
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
                elif op.type == X86_OP_IMM and (op.imm & 0xFFFFFFFFFFFFFFFF) - base in want:
                    hit = True
            if not hit:
                continue
            out.append("; ---- xref @ %#x ----" % ins.address)
            for j in range(max(0, idx - before), min(len(insns), idx + after + 1)):
                n = insns[j]
                out.append("%s%08x  %-16s %-7s %s"
                           % ("> " if j == idx else "  ", n.address, n.bytes.hex(),
                              n.mnemonic, n.op_str))
            out.append("")

    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "strxref.txt")
    io.open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("wrote %s (%d lines)" % (dst, len(out)))


main()
