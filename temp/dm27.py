"""dm27: settle the record framing once and for all by dumping the *whole*
initializer of one datamap as an ordered store trace.

Three framings are currently in play:
    dm10 : name at record+0x38, offset at +0x14, size at +0x1c
    dm24 : name at record+0x28, type at +0x00, offset at +0x04, size at +0x0c
    dm22 : name_dst - zero_fill_start = 0x28 for 1795 slots, 0x60 for 1398

Only the disassembly of a single initializer shows which disp the name pointer
is stored to, so this prints every RIP-relative lea (resolved to a string) and
every store to [reg+disp] with disp < 0x100, in program order, for
    0x1418d8d60  DT_HealthKit   (dm24's proof function)
    0x1420d8e70  DT_AI_BaseNPC  (from dm22's per-function table)
"""
import os
import struct

import capstone
import pefile

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
IMGBASE = 0x140000000
FUNCS = [0x1418d8d60, 0x1420d8e70]

pe = pefile.PE(PATH, fast_load=True)
raw = open(PATH, "rb").read()
secs = [(IMGBASE + s.VirtualAddress, s.Misc_VirtualSize, s.SizeOfRawData,
         s.PointerToRawData) for s in pe.sections]


def off(va):
    for sva, vs, rs, rp in secs:
        if sva <= va < sva + max(vs, rs):
            return rp + (va - sva)
    return None


def cstr(va, n=64):
    o = off(va)
    if o is None:
        return None
    e = raw.find(b"\x00", o, o + n)
    if e < 0:
        return None
    try:
        s = raw[o:e].decode("ascii")
    except UnicodeDecodeError:
        return None
    return s if s and all(32 <= ord(c) < 127 for c in s) else None


md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = True
out = []


def p(s=""):
    out.append(s)
    print(s)


for fn in FUNCS:
    p("=" * 78)
    p("### initializer %#x" % fn)
    p("=" * 78)
    o = off(fn)
    code = raw[o:o + 0x1800]
    last_lea = {}
    n = 0
    for ins in md.disasm(code, fn):
        n += 1
        if n > 900:
            break
        txt = "%#012x  %-26s %s" % (ins.address, ins.mnemonic,
                                    ins.op_str)
        note = ""
        # RIP-relative lea -> string
        for op in ins.operands:
            if op.type == capstone.x86.X86_OP_MEM and \
                    op.mem.base == capstone.x86.X86_REG_RIP:
                tgt = ins.address + ins.size + op.mem.disp
                s = cstr(tgt)
                if s:
                    note = "  ; '%s'" % s
            elif op.type == capstone.x86.X86_OP_MEM and op.mem.disp:
                pass
        # remember lea reg, [rip+str]
        if ins.mnemonic == "lea" and ins.operands[0].type == \
                capstone.x86.X86_OP_REG:
            for op in ins.operands[1:]:
                if op.type == capstone.x86.X86_OP_MEM and \
                        op.mem.base == capstone.x86.X86_REG_RIP:
                    tgt = ins.address + ins.size + op.mem.disp
                    s = cstr(tgt)
                    last_lea[ins.operands[0].reg] = (tgt, s)
        # stores to [reg+small disp]
        if ins.mnemonic.startswith("mov") or ins.mnemonic.startswith("vmov"):
            dst = None
            if ins.operands and ins.operands[0].type == \
                    capstone.x86.X86_OP_MEM:
                m = ins.operands[0].mem
                if m.base and m.disp < 0x100:
                    dst = "%s%+#x" % (ins.reg_name(m.base), m.disp)
            if dst:
                src = ins.operands[1] if len(ins.operands) > 1 else None
                sn = ""
                if src is not None:
                    if src.type == capstone.x86.X86_OP_REG:
                        sn = ins.reg_name(src.reg)
                        if src.reg in last_lea:
                            tva, tnm = last_lea[src.reg]
                            sn += " (=%s)" % ("'%s'" % tnm if tnm
                                              else "%#x" % tva)
                    elif src.type == capstone.x86.X86_OP_IMM:
                        sn = "%#x" % (src.imm & 0xffffffffffffffff)
                note = "   ; %s -> [%s] %s" % (sn or ins.op_str, dst, note)
        p(txt + note)
        if ins.mnemonic == "int3" and n > 8:
            break

with open(os.path.join(HERE, "dm27.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
p("")
p("wrote dm27.txt  (%d lines)" % len(out))
