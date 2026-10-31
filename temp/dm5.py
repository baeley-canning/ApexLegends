"""dm3/dm4 conclusion: no static table references any m_* field name, as a
pointer or as a 32-bit offset.  Only one mechanism is left: RIP-relative `lea`
(48/4C/49/4D 8D /r with mod=00, rm=101), i.e. names are consumed by code and the
matching field offset is an immediate near that instruction.

This script:
  * scans .text for every REX.W RIP-relative lea and records (site, target)
  * reports how many of the 2202 m_* strings are reached this way
  * dumps the instructions around the m_iHealth / m_iTeamNum / m_vecOrigin /
    m_lifeState sites and extracts candidate offset immediates (< 0x4c10)

Output: temp/dm5.txt
"""
import os
import struct
from collections import Counter

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
data = open(PATH, "rb").read()
out = []


def p(s=""):
    out.append(s)


e = struct.unpack_from("<I", data, 0x3C)[0]
image_base = struct.unpack_from("<Q", data, e + 0x18 + 0x18)[0]
nsec = struct.unpack_from("<H", data, e + 6)[0]
opt = struct.unpack_from("<H", data, e + 0x14)[0]
tab = e + 0x18 + opt
SEC = {}
order = []
for i in range(nsec):
    o = tab + 0x28 * i
    nm = data[o:o + 8].rstrip(b"\x00").decode("latin1")
    vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, o + 8)
    SEC[nm] = (va, vsize, rawptr, rawsize)
    order.append(nm)


def rva2off(rva):
    for nm in order:
        va, vsize, rawptr, rawsize = SEC[nm]
        if va <= rva < va + max(vsize, rawsize):
            d = rva - va
            return rawptr + d if d < rawsize else None
    return None


def off2rva(off):
    for nm in order:
        va, vsize, rawptr, rawsize = SEC[nm]
        if rawptr <= off < rawptr + rawsize:
            return va + (off - rawptr)
    return None


def cstr(rva, n=110):
    o = rva2off(rva)
    if o is None:
        return None
    b = data[o:o + n]
    z = b.find(b"\x00")
    return None if z <= 0 else b[:z].decode("latin1", "replace")


# m_* / field-name string set, from .rdata
ident = {}
for nm in (".rdata", ".data", "_RDATA", ".ooa"):
    if nm not in SEC:
        continue
    va, vsize, rawptr, rawsize = SEC[nm]
    blob = data[rawptr:rawptr + rawsize]
    i = blob.find(b"\x00")
    while 0 < i < min(vsize, rawsize) - 4:
        j = blob.find(b"\x00", i + 1)
        if j < 0:
            break
        s = blob[i + 1:j]
        if 2 < len(s) <= 96 and s[:1].isalpha() and all(32 < c < 127 for c in s):
            ident[va + i + 1] = s.decode("latin1")
        i = j
m_set = {k for k, v in ident.items() if v.startswith("m_")}
p("## census: %d identifiers, %d m_*" % (len(ident), len(m_set)))

# ---------------------------------------------------------------------------
# RIP-relative lea scan over .text
# ---------------------------------------------------------------------------
tva, tvsize, traw, trawsize = SEC[".text"]
text = data[traw:traw + trawsize]
NX = [i for i in range(len(text) - 7) if text[i] in (0x48, 0x4C, 0x49, 0x4D)
      and text[i + 1] == 0x8D and (text[i + 2] & 0xC7) == 0x05]
p("## REX.W rip-relative lea count in .text: %d" % len(NX))

targets = {}
for i in NX:
    disp = struct.unpack_from("<i", text, i + 3)[0]
    tgt = tva + i + 7 + disp
    targets.setdefault(tgt, []).append(tva + i)
p("  distinct targets: %d" % len(targets))
hit_m = [t for t in targets if t in m_set]
p("  of those landing on an m_* string: %d" % len(hit_m))
p("  sample: %s" % [(hex(t), ident[t]) for t in hit_m[:10]])

# sanity: how many lea targets land anywhere inside .rdata?
p("  lea targets inside .rdata: %d"
  % sum(1 for t in targets if SEC[".rdata"][0] <= t < SEC[".rdata"][0] + SEC[".rdata"][1]))

# ---------------------------------------------------------------------------
# Around specific field names: show code and candidate offset immediates
# ---------------------------------------------------------------------------
def show(name_rva, span=0x60):
    p("")
    p("## %r @ %#x  (%d sites)" % (cstr(name_rva), name_rva,
                                   len(targets.get(name_rva, []))))
    for site in targets.get(name_rva, [])[:6]:
        o = rva2off(site)
        code = data[o:o + span]
        p("  site %#010x  %s" % (site, code.hex(" ")))
        cand = []
        for k in range(0, len(code) - 4):
            v = struct.unpack_from("<I", code, k)[0]
            if 0 < v < 0x4C10 and v % 4 == 0:
                cand.append((k, v))
        p("    candidate offset immediates: %s"
          % ["+%#x=%#x" % c for c in cand[:14]])


for nm in ("m_iHealth", "m_iTeamNum", "m_lifeState", "m_vecOrigin",
           "m_iMaxHealth", "m_hOwnerEntity"):
    for rva, txt in ident.items():
        if txt == nm:
            show(rva)
            break

with open(os.path.join(HERE, "dm5.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
print("[written] temp/dm5.txt (%d lines)" % len(out))
