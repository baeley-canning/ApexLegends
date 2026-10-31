"""disasm_drv.py -- linear disassembly of a driver's .text, written to a file.

usage: python disasm_drv.py MsIo64.sys [start_rva] [len]
"""
import os
import struct
import sys

from capstone import Cs, CS_ARCH_X86, CS_MODE_64

DRV = os.path.join(os.environ["SystemRoot"], "System32", "drivers")


def sections(buf):
    e = struct.unpack_from("<I", buf, 0x3C)[0]
    nsec = struct.unpack_from("<H", buf, e + 6)[0]
    opt = struct.unpack_from("<H", buf, e + 20)[0]
    sec = e + 24 + opt
    out = {}
    for i in range(nsec):
        o = sec + i * 40
        name = buf[o:o + 8].rstrip(b"\x00").decode("ascii", "replace")
        vsize, vaddr, rsize, raddr = struct.unpack_from("<IIII", buf, o + 8)
        out[name] = (vaddr, raddr, max(vsize, rsize))
    return out


def main():
    name = sys.argv[1]
    start = int(sys.argv[2], 0) if len(sys.argv) > 2 else None
    length = int(sys.argv[3], 0) if len(sys.argv) > 3 else None

    path = os.path.join(DRV, name)
    buf = open(path, "rb").read()
    secs = sections(buf)
    vaddr, raddr, size = secs[".text"]
    code = buf[raddr:raddr + size]

    base = vaddr if start is None else start
    code = code[base - vaddr:]
    if length:
        code = code[:length]

    md = Cs(CS_ARCH_X86, CS_MODE_64)
    md.detail = False
    lines = ["; %s .text rva %#x..%#x" % (name, base, base + len(code))]
    for ins in md.disasm(code, base):
        lines.append("%08x  %-24s %s %s" % (ins.address, ins.bytes.hex(), ins.mnemonic, ins.op_str))

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "disasm_%s.txt" % os.path.splitext(name)[0])
    open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("wrote %s (%d insns)" % (out, len(lines) - 1))


main()
