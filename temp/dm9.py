"""Dump the WHOLE datamap-initializer function around chosen field names.

dm8 proved the initializer stores are recoverable, but a 0x700-byte window cuts
across record boundaries and mixes several parallel datamap arrays.  Here we:

  * find every `lea reg,[rip+"m_xxx"]` site,
  * grow each site to the enclosing function (padding/ret boundaries),
  * disassemble it linearly and print every instruction with the RIP-relative
    target annotated (and the string, when the target is a known name),

so the record layout can be read off in declaration order.

Output: temp/dm9.txt
"""
import os
import re
import struct

import capstone
import pefile

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
out = []


def p(s=""):
    out.append(s)
    if len(out) % 200 == 0:
        with open(os.path.join(HERE, "dm9_prog.txt"), "a", encoding="utf-8") as fh:
            fh.write("%d lines\n" % len(out))


pe = pefile.PE(PATH, fast_load=True)
base = pe.OPTIONAL_HEADER.ImageBase
secs = []
for s in pe.sections:
    secs.append((s.Name.rstrip(b"\x00").decode("latin1"),
                 base + s.VirtualAddress, s.Misc_VirtualSize,
                 s.SizeOfRawData, s.PointerToRawData, s.Characteristics))
data = open(PATH, "rb").read()


def find(va):
    for s in secs:
        nm, sva, vs, rs, rp, ch = s
        if sva <= va < sva + max(vs, rs):
            return s, va - sva
    return None, None


def rd(va, n):
    s, d = find(va)
    if s is None or d >= s[3]:
        return b"\x00" * n
    return data[s[4] + d:s[4] + d + n]


def cstr(va, n=80):
    b = rd(va, n)
    z = b.find(b"\x00")
    return None if z <= 0 else b[:z].decode("latin1", "replace")


# ---------------------------------------------------------------------------
# name strings (same vectorized scan as dm8)
# ---------------------------------------------------------------------------
ident = {}
pat = re.compile(rb"[\x20-\x7e]{3,96}")
for nm, sva, vs, rs, rp, ch in secs:
    if ch & 0x20 or rs > 0x800000:
        continue
    blob = data[rp:rp + rs]
    for m in pat.finditer(blob):
        e = m.end()
        if e < rs and blob[e] == 0 and m.group()[:1].isalpha():
            ident[sva + m.start()] = m.group().decode("latin1")
name_at = {k: v for k, v in ident.items() if v.startswith("m_")}

ts = next(s for s in secs if s[5] & 0x20)
text = data[ts[4]:ts[4] + ts[3]]
tva = ts[1]

leapat = re.compile(rb"[\x48\x4c\x49\x4d]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]")
by_name = {}
for m in leapat.finditer(text):
    i = m.start()
    tgt = tva + i + 7 + struct.unpack_from("<i", text, i + 3)[0]
    if tgt in name_at:
        by_name.setdefault(name_at[tgt], []).append(tva + i)

p("## %d names, %d lea sites" % (len(by_name), sum(len(v) for v in by_name.values())))
for k in ("m_iHealth", "m_iTeamNum", "m_vecOrigin", "m_lifeState"):
    p("   %-14s %d sites %s" % (k, len(by_name.get(k, [])),
                                 " ".join("%#x" % a for a in by_name.get(k, []))))


def off_va(va):
    return va - tva


def func_start(va):
    """walk back to padding (int3/nop run) or a ret, max 0x600 bytes"""
    lo = max(tva, va - 0x600)
    win = text[off_va(lo):off_va(va)]
    for pat_ in (b"\xcc\xcc\xcc\xcc\xcc", b"\xc3", b"\xc3\xcc", b"\xcc"):
        j = win.rfind(pat_)
        if j >= 0:
            return lo + j + len(pat_) if pat_ != b"\xc3" else lo + j + 1
    return lo


def func_end(va, limit=0x1200):
    hi = min(tva + len(text), va + limit)
    win = text[off_va(va):off_va(hi)]
    for pat_ in (b"\xcc\xcc\xcc\xcc\xcc", b"\xc3"):
        j = win.find(pat_)
        if j >= 0:
            return va + j + 1
    return hi


md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = True
md.skipdata = True
X86 = capstone.x86


def annotate(ins):
    """target address for a rip-relative operand + the immediate, if any"""
    tgt = None
    immv = None
    for op in ins.operands:
        if op.type == X86.X86_OP_MEM and op.mem.base == X86.X86_REG_RIP:
            tgt = ins.address + ins.size + op.mem.disp
        elif op.type == X86.X86_OP_IMM:
            immv = op.imm
    s = "%#012x  %-24s %s" % (ins.address, ins.bytes.hex(), ins.op_str)
    if tgt is not None:
        cs = cstr(tgt, 24) if tgt in ident else None
        s += "        ; -> %#x" % tgt
        if cs:
            s += " '%s'" % cs
    if immv is not None and tgt is not None:
        s += "  imm=%#x" % immv
    elif immv is not None:
        s += "        ; imm=%#x" % immv
    return s


for nm in ("m_iHealth", "m_iTeamNum", "m_vecOrigin", "m_lifeState"):
    for site in by_name.get(nm, [])[:2]:
        a, b = func_start(site), func_end(site)
        p("")
        p("### %s  lea@%#x   function %#x..%#x  (%d bytes)"
          % (nm, site, a, b, b - a))
        code = rd(a, b - a)
        for ins in md.disasm(code, a):
            if ins.id == 0:
                p("%#012x  %-24s .byte" % (ins.address, ins.bytes.hex()))
                continue
            p(annotate(ins))

with open(os.path.join(HERE, "dm9.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
print("[written] temp/dm9.txt (%d lines)" % len(out))
