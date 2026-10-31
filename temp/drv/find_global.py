"""find_global.py -- locate writes to a driver global (default RVA 0x3150).

MsIo64's map handler (0x1090) gates on a dword global read at 0x10aa:

    eax = [rip + 0x20a0]          ; RVA 0x3150
    if (eax == 0)                 -> STATUS_ACCESS_DENIED
    if ((u32)addr <  eax)        -> STATUS_ACCESS_DENIED
    if ((u32)addr <= eax + 0x10000000) -> OK

so the runtime value of that global decides which "addresses" the
0x80102040 map IOCTL accepts.  DriverEntry lives at RVA 0x5010, i.e. far
outside the 0x1000..0x1960 window of the earlier annotation, so this
script scans the whole .text and prints

  * the on-disk initial value at the RVA, and
  * every instruction that stores to that RVA (with 4 lines of context).

usage:  python find_global.py <driver.sys> [target_rva]
"""
import os
import sys

import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64
from capstone.x86 import X86_OP_MEM, X86_REG_RIP

DRV = os.path.join(os.environ["SystemRoot"], "System32", "drivers")
WRITE_MNEMONICS = ("mov", "movzx", "movsx", "movsxd", "add", "sub", "or", "and",
                   "xor", "inc", "dec", "xchg", "shl", "shr", "bswap", "not",
                   "neg", "imul", "movbe")


def load(path):
    pe = pefile.PE(path, fast_load=False)
    base = pe.OPTIONAL_HEADER.ImageBase
    iat = {}
    for entry in getattr(pe, "DIRECTORY_ENTRY_IMPORT", []):
        dll = entry.dll.decode("ascii", "replace").split(".")[0]
        for imp in entry.imports:
            name = imp.name.decode("ascii", "replace") if imp.name else "#%d" % imp.ordinal
            iat[imp.address - base] = "%s!%s" % (dll, name)
    return pe, base, iat


def rva2off(pe, rva):
    for s in pe.sections:
        lo = s.VirtualAddress
        hi = lo + max(s.Misc_VirtualSize, s.SizeOfRawData)
        if lo <= rva < hi:
            return s.PointerToRawData + (rva - lo)
    return None


def main():
    name = sys.argv[1]
    target = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x3150
    path = name if os.path.isabs(name) else os.path.join(DRV, name)
    pe, base, iat = load(path)
    buf = open(path, "rb").read()

    out = ["; %s  imagebase=%#x  entry=%#x  target=%#x"
           % (os.path.basename(path), base,
              pe.OPTIONAL_HEADER.AddressOfEntryPoint, target), ""]

    off = rva2off(pe, target)
    if off is None:
        out.append("target RVA not inside any section")
    else:
        lo = max(0, off - 0x20)
        out.append("; --- bytes around target (file off %#x, rva %#x) ---" % (off, target))
        for i in range(lo, off + 0x20, 16):
            chunk = buf[i:i + 16]
            txt = " ".join("%02x" % b for b in chunk)
            asc = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
            mark = "  <== %#x" % (base + target) if i <= off < i + 16 else ""
            out.append("%08x  %-47s  %s%s" % (i, txt, asc, mark))
    out.append("")

    md = Cs(CS_ARCH_X86, CS_MODE_64)
    md.detail = True
    hits = 0
    for s in pe.sections:
        if not (s.Characteristics & 0x20000000):  # IMAGE_SCN_MEM_EXECUTE
            continue
        code = buf[s.PointerToRawData:s.PointerToRawData + s.SizeOfRawData]
        insns = list(md.disasm(code, s.VirtualAddress))
        for idx, ins in enumerate(insns):
            if ins.mnemonic not in WRITE_MNEMONICS or not ins.operands:
                continue
            dst = ins.operands[0]
            if dst.type != X86_OP_MEM or dst.mem.base != X86_REG_RIP:
                continue
            tgt = ins.address + ins.size + dst.mem.disp
            if tgt != target:
                continue
            hits += 1
            out.append("; --- write @ %#x : %s %s" % (ins.address, ins.mnemonic, ins.op_str))
            for j in range(max(0, idx - 6), min(len(insns), idx + 3)):
                n = insns[j]
                note = ""
                if n.mnemonic in ("call", "jmp") and n.operands \
                        and n.operands[0].type == X86_OP_MEM \
                        and n.operands[0].mem.base == X86_REG_RIP:
                    note = " ; " + iat.get(n.address + n.size + n.operands[0].mem.disp,
                                           "?")
                out.append("%s%08x  %-16s %-7s %s%s"
                           % ("> " if j == idx else "  ", n.address, n.bytes.hex(),
                              n.mnemonic, n.op_str, note))
            out.append("")
    if not hits:
        out.append("; no direct store to %#x found" % target)

    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "global_%x.txt" % target)
    open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("wrote %s (%d hits)" % (dst, hits))


main()
