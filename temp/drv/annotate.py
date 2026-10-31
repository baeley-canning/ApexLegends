"""annotate.py -- annotated disassembly of a kernel driver.

Why: the earlier dumps (disasm_drv.py) showed `call qword ptr [rip + 0xab3]`
with no name, which left the MsIo64 map/read handlers ambiguous.  This resolves
every indirect call/jmp through the import table, and tags

  * `mov qword ptr [reg + 0x70], reg`  -> IRP_MJ_DEVICE_CONTROL slot of a
    DRIVER_OBJECT (MajorFunction[0xE]); 0x60 = IRP_MJ_CREATE etc.
  * any cmp against an imm32 with the CTL_CODE device bit set

usage:  python annotate.py <driver.sys> [start_rva [end_rva]]
"""
import os
import sys

import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64
from capstone.x86 import (X86_OP_IMM, X86_OP_MEM, X86_OP_REG, X86_REG_RIP)

DRV = os.path.join(os.environ["SystemRoot"], "System32", "drivers")
HERE = os.path.dirname(os.path.abspath(__file__))

MAJOR = {0x60: "IRP_MJ_CREATE", 0x68: "IRP_MJ_CLOSE", 0x70: "IRP_MJ_DEVICE_CONTROL",
         0x78: "IRP_MJ_INTERNAL_DEVICE_CONTROL", 0x80: "IRP_MJ_CLEANUP",
         0x88: "IRP_MJ_SHUTDOWN", 0x58: "IRP_MJ_READ", 0x50: "IRP_MJ_WRITE"}


def load(path):
    pe = pefile.PE(path, fast_load=False)
    base = pe.OPTIONAL_HEADER.ImageBase
    iat = {}
    for entry in getattr(pe, "DIRECTORY_ENTRY_IMPORT", []):
        dll = entry.dll.decode("ascii", "replace")
        for imp in entry.imports:
            if imp.name:
                iat[imp.address - base] = "%s!%s" % (dll.split(".")[0],
                                                     imp.name.decode("ascii", "replace"))
            else:
                iat[imp.address - base] = "%s!#%d" % (dll.split(".")[0], imp.ordinal)
    secs = []
    for s in pe.sections:
        secs.append((s.Name.rstrip(b"\x00").decode("ascii", "replace"),
                     s.VirtualAddress,
                     s.PointerToRawData,
                     max(s.Misc_VirtualSize, s.SizeOfRawData),
                     s.SizeOfRawData))
    return pe, base, iat, secs


def disasm_range(pe, buf, secs, text_name, start, end):
    for name, va, off, size, raw in secs:
        if name == text_name:
            break
    else:
        raise SystemExit("no section %s" % text_name)
    lo, hi = va, va + min(size, raw)
    if start is not None:
        lo = max(lo, start)
    if end is not None:
        hi = min(hi, end)
    code = buf[off + (lo - va): off + (hi - va)]
    md = Cs(CS_ARCH_X86, CS_MODE_64)
    md.detail = True
    return md.disasm(code, lo)


def annotate(path, text_name, start, end):
    pe, base, iat, secs = load(path)
    buf = open(path, "rb").read()
    entry = pe.OPTIONAL_HEADER.AddressOfEntryPoint
    out = ["; %s  imagebase=%#x  entry=%#x" % (os.path.basename(path), base, entry),
           "; imports: %d" % len(iat)]
    names = sorted(set(v for v in iat.values() if "!" in v))
    out += [";   " + ", ".join(names[i:i + 4]) for i in range(0, len(names), 4)]
    out.append("")

    for ins in disasm_range(pe, buf, secs, text_name, start, end):
        note = ""
        if ins.mnemonic in ("call", "jmp") and ins.operands \
                and ins.operands[0].type == X86_OP_MEM \
                and ins.operands[0].mem.base == X86_REG_RIP:
            tgt = ins.address + ins.size + ins.operands[0].mem.disp
            note = iat.get(tgt, "qword_%x" % tgt)
        elif ins.mnemonic == "mov" and len(ins.operands) == 2 \
                and ins.operands[0].type == X86_OP_MEM and ins.operands[1].type == X86_OP_REG:
            m = ins.operands[0].mem
            if m.base != 0 and m.index == 0 and m.disp in MAJOR:
                note = "<- %s slot" % MAJOR[m.disp]
        elif ins.mnemonic == "cmp" and len(ins.operands) == 2 \
                and ins.operands[1].type == X86_OP_IMM:
            imm = ins.operands[1].imm & 0xFFFFFFFF
            if imm >= 0x80000000 and 0x800 <= ((imm >> 2) & 0xFFF) <= 0xFFF \
                    and ((imm >> 16) & 0xFFFF) >= 0x8000:
                note = "** IOCTL? %#010x  dev=%#x fn=%#x method=%d access=%d" % (
                    imm, (imm >> 16) & 0xFFFF, (imm >> 2) & 0xFFF, imm & 3,
                    (imm >> 14) & 3)
            elif imm >= 0x80000000:
                note = "imm %#x" % imm
        line = "%08x  %-22s %-7s %s" % (ins.address, ins.bytes.hex(), ins.mnemonic,
                                         ins.op_str)
        if note:
            line = "%-72s ; %s" % (line, note)
        out.append(line.rstrip())
    return out


def main():
    name = sys.argv[1]
    start = int(sys.argv[2], 0) if len(sys.argv) > 2 else None
    end = int(sys.argv[3], 0) if len(sys.argv) > 3 else None
    path = name if os.path.isabs(name) else os.path.join(DRV, name)
    text = annotate(path, ".text", start, end)
    tag = os.path.splitext(os.path.basename(name))[0]
    if start is not None:
        tag += "_%x" % start
    out = os.path.join(HERE, "annot_%s.txt" % tag)
    open(out, "w", encoding="utf-8").write("\n".join(text) + "\n")
    print("wrote %s (%d lines)" % (out, len(text)))


main()
