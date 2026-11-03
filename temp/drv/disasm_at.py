"""disasm around an arbitrary RVA in whatever section holds it (gdrv3 W3 work)."""
import os
import sys

import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

DRV = os.path.join(os.environ["SystemRoot"], "System32", "drivers")
name, rva, back, fwd = sys.argv[1], int(sys.argv[2], 0), int(sys.argv[3], 0), int(sys.argv[4], 0)
path = os.path.join(DRV, name)
pe = pefile.PE(path)
buf = open(path, "rb").read()
out = ["; %s imagebase=%#x target=%#x" % (name, pe.OPTIONAL_HEADER.ImageBase, rva)]
for s in pe.sections:
    out.append("; sec %s va=%#x vsize=%#x raw=%#x rsize=%#x flags=%#x"
               % (s.Name.rstrip(b"\x00").decode("ascii", "replace"), s.VirtualAddress,
                  s.Misc_VirtualSize, s.PointerToRawData, s.SizeOfRawData, s.Characteristics))
sec = None
for s in pe.sections:
    if s.VirtualAddress <= rva < s.VirtualAddress + max(s.Misc_VirtualSize, s.SizeOfRawData):
        sec = s
        break
if sec is None:
    out.append("; RVA not in any section")
else:
    start = max(sec.VirtualAddress, rva - back)
    end = min(sec.VirtualAddress + sec.SizeOfRawData, rva + fwd)
    off = sec.PointerToRawData + (start - sec.VirtualAddress)
    code = buf[off:off + (end - start)]
    md = Cs(CS_ARCH_X86, CS_MODE_64)
    for ins in md.disasm(code, start):
        out.append("%08x  %-24s %s %s" % (ins.address, ins.bytes.hex(), ins.mnemonic, ins.op_str))
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "disasm_at.txt")
open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
print("wrote %s" % dst)
