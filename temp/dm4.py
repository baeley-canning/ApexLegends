"""Hypothesis: the m_* names live in one contiguous blob and the field tables
reference them as 32-bit OFFSETS from the blob base (not as pointers).  dm3 proved
no pointer points at any of the 2202 m_* strings, so this is the remaining
explanation that keeps the datamaps static.

Tests, for four anchor names:
  * locate the containing NUL-terminated string blob and compute its base rva
  * search the whole file for u32 == (string_rva - base), also u16/u8 variants
  * for every u32 hit, dump the surrounding 0x40 record with
        name = blob[base + u32@+0x10], offset = u32@+0x18, size = u32@+0x1C
    so a real datamap would print out field-name/offset/size triples.

Output: temp/dm4.txt
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


def off2rva(off):
    for nm, va, vsize, rawptr, rawsize in SEC:
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


def blobby(o):
    """True if byte can be part of a packed string blob."""
    return o == 0 or 0x20 <= o <= 0x7E


anchors = (0x0305C850, 0x030666A0, 0x030C8C78, 0x0307A9E0)
p("## blob bases")
for a in anchors:
    o = rva2off(a)
    if o is None:
        p("  %#x not raw-backed" % a)
        continue
    s = o
    while s > 0 and blobby(data[s - 1]):
        s -= 1
    t = o
    while t < len(data) and blobby(data[t]):
        t += 1
    p("  string %#010x %-16r blob rva %#010x..%#010x  (%d bytes)"
      % (a, cstr(a), off2rva(s), off2rva(t), t - s))
    for probe_base in (off2rva(s),):
        pass

# --------------------------------------------------------------------------
# For each anchor: try u32/u16 offsets from the blob base that starts the run.
# --------------------------------------------------------------------------
p("")
p("## offset-reference test (u32 relative to blob base)")
for a in anchors:
    o = rva2off(a)
    s = o
    while s > 0 and blobby(data[s - 1]):
        s -= 1
    base = off2rva(s)
    p("  anchor %#010x base %#010x (delta %#x) %r"
      % (a, base, a - base, cstr(a)))
    for width, fmt in ((4, "<I"), (2, "<H")):
        val = a - base
        if width == 2 and val > 0xFFFF:
            continue
        pat = struct.pack(fmt, val)
        hits, pos = [], data.find(pat)
        while pos != -1:
            r = off2rva(pos)
            if r is not None:
                hits.append((r, pos))
            pos = data.find(pat, pos + 1)
        p("    u%d==%#x hits: %d %s" % (width * 8, val, len(hits),
                                        [hex(h[0]) for h in hits[:10]]))
        if hits:
            for r, pos in hits[:4]:
                p("      hit at rva %#010x:" % r)
                for k in range(-3, 4):
                    o2 = rva2off(r + 4 * k)
                    if o2 is None:
                        continue
                    v = struct.unpack_from("<I", data, o2)[0]
                    nm = cstr(base + v) if v < 0x1000000 else None
                    p("        %#010x u32=%#010x %r" % (r + 4 * k, v, nm))

# --------------------------------------------------------------------------
# Any u32 cluster that resolves to m_ names?  Direct: scan .data for u32 values
# whose (section-relative) target string starts with "m_" and report strides.
# --------------------------------------------------------------------------
p("")
p("## arbitrary-base sweep: u32 values that land on an m_* string")
res = {}
for nm, va, vsize, rawptr, rawsize in SEC:
    if nm != ".data":
        continue
    blob = data[rawptr:rawptr + rawsize]
    for off in range(0, len(blob) - 4, 4):
        v = struct.unpack_from("<I", blob, off)[0]
        if v < 0x2C97000 or v > 0x3318000:
            continue
        s = cstr(v, 12)
        if s and s.startswith("m_"):
            res.setdefault(v, []).append(va + off)
p("  distinct m_* string rvas referenced as u32: %d" % len(res))
for v in list(res)[:8]:
    p("    %#010x %-20r %d refs %s" % (v, cstr(v), len(res[v]),
                                       [hex(x) for x in res[v][:4]]))

with open(os.path.join(HERE, "dm4.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
print("[written] temp/dm4.txt (%d lines)" % len(out))
