"""Decode the runtime datamap registration code.

For every `lea reg,[rip+str]` landing on a field name, walk forward over the run
of RIP-relative stores and record (dest_rva, width, value).  Group the stores by
dest so the descriptor layout can be inferred: the record that holds the name
pointer should also hold offset / size / flags as immediates.

Output: temp/dm6.txt
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
SEC, order = {}, []
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


def cstr(rva, n=100):
    o = rva2off(rva)
    if o is None:
        return None
    b = data[o:o + n]
    z = b.find(b"\x00")
    return None if z <= 0 else b[:z].decode("latin1", "replace")


tva, tvsize, traw, trawsize = SEC[".text"]
text = data[traw:traw + trawsize]
N = len(text)


def store_at(i):
    """Decode one RIP-relative store/lea at text offset i.

    Returns (length, dest_rva, width, kind, imm) or None.
    kind: imm | reg | lea | load
    """
    b = text

    def rip(disp_off, end):
        d = struct.unpack_from("<i", b, i + disp_off)[0]
        return tva + i + end + d

    if b[i] == 0x0F and b[i + 1] == 0x11 and (b[i + 2] & 0xC7) == 0x05:
        return 8, rip(3, 8), 16, "reg", None
    if b[i] == 0xF2 and b[i + 1] == 0x0F and b[i + 2] == 0x11 and (b[i + 3] & 0xC7) == 0x05:
        return 9, rip(4, 9), 8, "reg", None
    if b[i] == 0xF3 and b[i + 1] == 0x0F and b[i + 2] == 0x11 and (b[i + 3] & 0xC7) == 0x05:
        return 9, rip(4, 9), 4, "reg", None
    if b[i] == 0x48 and b[i + 1] == 0xC7 and (b[i + 2] & 0xC7) == 0x05:
        return 11, rip(3, 11), 8, "imm", struct.unpack_from("<i", b, i + 7)[0] & 0xFFFFFFFF
    if b[i] == 0xC7 and (b[i + 1] & 0xC7) == 0x05:
        return 10, rip(2, 10), 4, "imm", struct.unpack_from("<i", b, i + 6)[0] & 0xFFFFFFFF
    if b[i] == 0x66 and b[i + 1] == 0xC7 and (b[i + 2] & 0xC7) == 0x05:
        return 9, rip(3, 9), 2, "imm", struct.unpack_from("<H", b, i + 7)[0]
    if b[i] == 0xC6 and (b[i + 1] & 0xC7) == 0x05:
        return 7, rip(2, 7), 1, "imm", b[i + 6]
    if b[i] == 0x48 and b[i + 1] == 0x89 and (b[i + 2] & 0xC7) == 0x05:
        return 7, rip(3, 7), 8, "reg", None
    if b[i] == 0x89 and (b[i + 1] & 0xC7) == 0x05:
        return 6, rip(2, 6), 4, "reg", None
    if b[i] == 0x44 and b[i + 1] == 0x89 and (b[i + 2] & 0xC7) == 0x05:
        return 7, rip(3, 7), 4, "reg", None
    if b[i] == 0x4C and b[i + 1] == 0x89 and (b[i + 2] & 0xC7) == 0x05:
        return 7, rip(3, 7), 8, "reg", None
    if b[i] == 0x66 and b[i + 1] == 0x89 and (b[i + 2] & 0xC7) == 0x05:
        return 8, rip(3, 8), 2, "reg", None
    if b[i] in (0x48, 0x4C) and b[i + 1] == 0x8D and (b[i + 2] & 0xC7) == 0x05:
        return 7, rip(3, 7), 8, "lea", None
    if b[i] == 0x0F and b[i + 1] == 0x10 and (b[i + 2] & 0xC7) == 0x05:
        return 8, rip(3, 8), 16, "load", None
    if b[i] == 0xF2 and b[i + 1] == 0x0F and b[i + 2] == 0x10 and (b[i + 3] & 0xC7) == 0x05:
        return 9, rip(4, 9), 8, "load", None
    return None


def walk(i, max_ins=32):
    seq, cur = [], i
    for _ in range(max_ins):
        got = store_at(cur)
        if got is None:
            break
        ln, dst, w, kind, imm = got
        seq.append((tva + cur, dst, w, kind, imm))
        cur += ln
    return seq


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

lea_sites = []
for i in range(N - 7):
    if text[i] in (0x48, 0x4C, 0x49, 0x4D) and text[i + 1] == 0x8D \
            and (text[i + 2] & 0xC7) == 0x05:
        d = struct.unpack_from("<i", text, i + 3)[0]
        tgt = tva + i + 7 + d
        if tgt in m_set:
            lea_sites.append((i, tgt))
p("## field-name lea sites: %d over %d distinct names"
  % (len(lea_sites), len({t for _, t in lea_sites})))


def dump(name, limit=2):
    p("")
    p("### %s" % name)
    n = 0
    for i, tgt in lea_sites:
        if ident[tgt] != name:
            continue
        n += 1
        if n > limit:
            break
        seq = walk(i, 32)
        if not seq:
            p("  site %#010x : no stores followed" % (tva + i))
            continue
        base = seq[0][1]
        p("  site %#010x  %d insns, dests %#x..%#x"
          % (tva + i, len(seq), min(s[1] for s in seq), max(s[1] for s in seq)))
        for va, dst, w, kind, imm in seq:
            val = ("imm=%#x" % imm) if kind == "imm" else kind
            p("    %#010x  dst %#010x (%+#06x) w=%2d %-4s %s"
              % (va, dst, dst - base, w, kind, val))


for nm in ("m_iHealth", "m_iTeamNum", "m_lifeState", "m_iMaxHealth",
           "m_vecOrigin", "m_hOwnerEntity"):
    dump(nm, 2)

dests = {}
for i, tgt in lea_sites:
    for va, dst, w, kind, imm in walk(i, 32):
        dests.setdefault(dst, []).append((kind, imm, ident[tgt], va))
p("")
p("## distinct descriptor destinations: %d" % len(dests))
ks = sorted(dests)
p("  min %#x  max %#x  span %#x" % (ks[0], ks[-1], ks[-1] - ks[0]))
gaps = {}
for a, b in zip(ks, ks[1:]):
    gaps[b - a] = gaps.get(b - a, 0) + 1
p("  most common dest gaps: %s"
  % sorted(gaps.items(), key=lambda kv: -kv[1])[:8])

with open(os.path.join(HERE, "dm6.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
print("[written] temp/dm6.txt (%d lines)" % len(out))
