"""
dm31: full static disassembly of a datamap initializer with every RIP-relative
target resolved (section + string), so the header stores can be read with the
real register context.

Usage: python dm31.py <hex_fn> [<hex_fn> ...]
Output: temp/dm31_<fn>.txt
"""
import os
import sys

import capstone
import pefile

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
IMGBASE = 0x140000000

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


def secname(va):
    s = sec_of(va)
    return "?" if s is None else "%s+%#x" % (s[0], va - s[1])


def cstr(va, n=80):
    s = sec_of(va)
    if s is None:
        return None
    d = va - s[1]
    if d >= s[3]:
        return None
    o = s[4] + d
    e = raw.find(b"\x00", o, o + n)
    if e < 0:
        return None
    try:
        t = raw[o:e].decode("ascii")
    except UnicodeDecodeError:
        return None
    return t if t and all(32 <= ord(c) < 127 for c in t) else None


md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = True

for arg in sys.argv[1:]:
    fn = int(arg, 16)
    s = sec_of(fn)
    off = s[4] + (fn - s[1])
    lines = []
    n = 0
    for ins in md.disasm(raw[off:off + 0x4000], fn):
        n += 1
        if ins.mnemonic == "int3" and n > 4:
            break
        note = ""
        for op in ins.operands:
            if op.type == capstone.x86.X86_OP_MEM and op.mem.base == \
                    capstone.x86.X86_REG_RIP:
                t = ins.address + ins.size + op.mem.disp
                note += "  ; %#x %s" % (t, secname(t))
                st = cstr(t)
                if st:
                    note += " '%s'" % st
        lines.append("  %#x  %-8s %-42s%s"
                     % (ins.address, ins.mnemonic, ins.op_str, note))
    dst = os.path.join(HERE, "dm31_%x.txt" % fn)
    with open(dst, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("wrote %s (%d insns)" % (dst, len(lines)))
