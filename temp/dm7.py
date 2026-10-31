"""Disassemble the code around field-name lea sites with capstone.

Answers the open question from dm6: what are the RIP-relative stores that
follow `lea rax, [rip+"m_iHealth"]`, and do they form a field descriptor?

Output: temp/dm7.txt
"""
import os
import struct

import capstone
import pefile

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
out = []


def p(s=""):
    out.append(s)


pe = pefile.PE(PATH, fast_load=True)
image_base = pe.OPTIONAL_HEADER.ImageBase
secs = []
for s in pe.sections:
    nm = s.Name.rstrip(b"\x00").decode("latin1")
    secs.append((nm, image_base + s.VirtualAddress, s.Misc_VirtualSize,
                 s.SizeOfRawData, s.PointerToRawData, s.Characteristics))
p("## sections")
for nm, va, vs, rs, rp, ch in secs:
    p("  %-10s va=%#012x vsize=%#010x raw=%#010x  %s"
      % (nm, va, vs, rs, "CODE" if ch & 0x20 else
         ("DATA" if ch & 0x40 else "")))

data = open(PATH, "rb").read()


def read(va, n):
    for nm, sva, vs, rs, rp, ch in secs:
        if sva <= va < sva + max(vs, rs):
            d = va - sva
            if d >= rs:
                return None
            return data[rp + d:rp + d + n]
    return None


def cstr(va, n=64):
    b = read(va, n)
    if not b:
        return None
    z = b.find(b"\x00")
    return None if z <= 0 else b[:z].decode("latin1", "replace")


# ---------------------------------------------------------------------------
# all lea sites onto m_* names, same scan as dm6 but VA-based
# ---------------------------------------------------------------------------
text_sec = next(s for s in secs if s[5] & 0x20)
tva, tvs, trs, trp = text_sec[1], text_sec[2], text_sec[3], text_sec[4]
text = data[trp:trp + trs]

ident = {}
for nm, sva, vs, rs, rp, ch in secs:
    if ch & 0x20:
        continue
    blob = data[rp:rp + rs]
    i = blob.find(b"\x00")
    while 0 < i < rs - 4:
        j = blob.find(b"\x00", i + 1)
        if j < 0:
            break
        s = blob[i + 1:j]
        if 2 < len(s) <= 96 and s[:1].isalpha() and all(32 < c < 127 for c in s):
            ident[sva + i + 1] = s.decode("latin1")
        i = j
m_set = {k for k, v in ident.items() if v.startswith("m_")}

sites = []
for i in range(len(text) - 7):
    if text[i] in (0x48, 0x4C, 0x49, 0x4D) and text[i + 1] == 0x8D \
            and (text[i + 2] & 0xC7) == 0x05:
        d = struct.unpack_from("<i", text, i + 3)[0]
        tgt = tva + i + 7 + d
        if tgt in m_set:
            sites.append((tva + i, tgt))
p("")
p("## lea sites onto m_* names: %d over %d names"
  % (len(sites), len({t for _, t in sites})))

lookup = {}
for va, tgt in sites:
    lookup.setdefault(ident[tgt], []).append(va)

md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = True
md.skipdata = True


def disasm(start, count=28, back=40):
    p("")
    p("### disasm from %#x" % start)
    code = read(start, 15 * count)
    for ins in md.disasm(code, start, ):
        if ins.address - start > 600:
            break
        ann = ""
        for op in ins.operands:
            if op.type == capstone.x86.X86_OP_MEM and op.mem.base == capstone.x86.X86_REG_RIP:
                t = ins.address + ins.size + op.mem.disp
                s = cstr(t)
                ann = "   ; %#x%s" % (t, (" " + repr(s)) if s else "")
                break
        p("  %#012x  %-8s %-42s%s" % (ins.address, ins.mnemonic, ins.op_str, ann))
        count -= 1
        if count <= 0 or ins.mnemonic == "ret":
            break


for name in ("m_iHealth", "m_iTeamNum", "m_vecOrigin"):
    for va in lookup.get(name, [])[:1]:
        p("")
        p("### context for %s @ %#x" % (name, va))
        disasm(va - 40, 30)

with open(os.path.join(HERE, "dm7.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
print("[written] temp/dm7.txt (%d lines)" % len(out))
