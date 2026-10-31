"""Result #2 says: no pointer anywhere points at m_iHealth / m_iTeamNum /
m_vecOrigin / m_currentFrame (qword OR u32).  Decide whether that is specific to
those four names, or true of every m_* field name -- and identify the table at
0x3354b20 by decoding its actual strings.

Output: temp/dm3.txt
"""
import os
import struct

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
SEC = []
for i in range(nsec):
    o = tab + 0x28 * i
    nm = data[o:o + 8].rstrip(b"\x00").decode("latin1")
    vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, o + 8)
    SEC.append((nm, va, vsize, rawptr, rawsize))


def rva2off(rva):
    for nm, va, vsize, rawptr, rawsize in SEC:
        if va <= rva < va + max(vsize, rawsize):
            d = rva - va
            return rawptr + d if d < rawsize else None
    return None


def cstr(rva, n=120):
    o = rva2off(rva)
    if o is None:
        return None
    b = data[o:o + n]
    z = b.find(b"\x00")
    return None if z <= 0 else b[:z].decode("latin1", "replace")


# --------------------------------------------------------------------------
# A. Every identifier string that IS referenced, bucketed by prefix.
# --------------------------------------------------------------------------
ident = {}
for nm, va, vsize, rawptr, rawsize in SEC:
    if nm not in (".rdata", ".data", "_RDATA", ".ooa"):
        continue
    blob = data[rawptr:rawptr + rawsize]
    i = blob.find(b"\x00")
    while 0 < i < min(vsize, rawsize) - 4:
        j = blob.find(b"\x00", i + 1)
        if j < 0:
            break
        s = blob[i + 1:j]
        if 3 <= len(s) <= 96 and s[:1].isalpha() and all(32 < c < 127 for c in s):
            ident[va + i + 1] = s.decode("latin1")
        i = j

referenced = set()
for nm, va, vsize, rawptr, rawsize in SEC:
    if nm not in (".rdata", ".data"):
        continue
    blob = data[rawptr:rawptr + rawsize]
    for off in range(0, len(blob) - len(blob) % 8, 8):
        q = struct.unpack_from("<Q", blob, off)[0]
        if image_base <= q <= image_base + 0x10000000:
            referenced.add(q - image_base)

m_names = [v for v in ident.values() if v.startswith("m_")]
m_ref = [v for k, v in ident.items() if v.startswith("m_") and k in referenced]
p("## prefix census")
p("  identifier strings      : %d" % len(ident))
p("  referenced by qword     : %d" % len(referenced))
p("  m_* strings             : %d   of which referenced: %d"
  % (len(m_names), len(m_ref)))
p("  m_* referenced sample   : %s" % m_ref[:20])
c_names = [v for k, v in ident.items() if v.startswith("C_") and len(v) > 4]
c_ref = [v for k, v in ident.items() if v.startswith("C_") and k in referenced]
p("  C_* strings             : %d   of which referenced: %d"
  % (len(c_names), len(c_ref)))

# --------------------------------------------------------------------------
# B. Decode the 0x3354b20 table for real.
# --------------------------------------------------------------------------
p("")
p("## 0x3354b20 decoded (stride 0x40)")
for i in range(20):
    r = 0x3354b20 + 0x40 * i
    o = rva2off(r)
    if o is None:
        break
    q0, q1, q2 = struct.unpack_from("<QQQ", data, o)
    a, b, c, d = struct.unpack_from("<4I", data, o + 0x18)
    p("  %#010x  +00=%#x +08=%#x +10=%#x %-22r | +18=%#x +1c=%#x +20=%#x +24=%#x"
      % (r, q0, q1, q2, cstr(q2 - image_base) if q2 > image_base else None,
         a, b, c, d))

p("")
p("## three refs to the string at 0x3082e38 -> what surrounds each")
o0 = rva2off(0x3082e38)
p("  0x3082e38 = %r" % cstr(0x3082e38))
pat = struct.pack("<Q", image_base + 0x3082e38)
pos = data.find(pat)
while pos != -1:
    # find containing rva
    rva = None
    for nm, va, vsize, rawptr, rawsize in SEC:
        if rawptr <= pos < rawptr + rawsize:
            rva = va + (pos - rawptr)
    if rva is not None:
        p("  ref at %#010x   (string at data offset %#x)" % (rva, pos))
        for k in range(-4, 5):
            rr = rva + 8 * k
            oo = rva2off(rr)
            if oo is None:
                continue
            v = struct.unpack_from("<Q", data, oo)[0]
            s = cstr(v - image_base) if v > image_base else None
            p("    %#010x  q=%#018x  %r" % (rr, v, s))
    pos = data.find(pat, pos + 1)

with open(os.path.join(HERE, "dm3.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
print("[written] temp/dm3.txt (%d lines)" % len(out))
