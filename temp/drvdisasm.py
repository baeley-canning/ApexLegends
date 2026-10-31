"""drvdisasm.py -- linear-sweep disassembly of the IOCTL dispatch in gdrv3.sys
and MsIo64.sys, so the input struct layouts can be read off the code instead of
guessed (a wrong struct into MmMapIoSpace is a BSOD).

usage: drvdisasm.py <file.sys> <va> <length>
       drvdisasm.py <file.sys> --sections
Branch/call targets print as real VAs.  Writes disasm_<name>_<va>.txt.
"""
import os
import sys

import capstone

import pedrv


def main():
    path = sys.argv[1]
    if sys.argv[2] == "--sections":
        print("\n".join(pedrv.dump_sections(path)))
        return
    va, ln = int(sys.argv[2], 0), int(sys.argv[3], 0)
    data, _secs = pedrv.sections(path)
    off = pedrv.va2off(path, va)
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = False
    lines = ["== %s  va %#x (file %#x) .. %#x"
             % (os.path.basename(path), va, off, va + ln)]
    for ins in md.disasm(data[off:off + ln], va):
        lines.append("  %#08x  %-20s %-8s %s"
                     % (ins.address, ins.bytes.hex(), ins.mnemonic, ins.op_str))
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "disasm_%s_%x.txt" % (os.path.basename(path).split(".")[0], va))
    open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print(out, len(lines) - 1, "instructions")


if __name__ == "__main__":
    main()
