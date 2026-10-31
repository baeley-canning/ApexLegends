"""Datamap forensics #2 -- stop guessing the layout, measure it.

Open question from dm_probe.txt: "C_BaseEntity" is referenced by three absolute
qwords, but "m_iHealth" has *no* qword reference anywhere in the file.  A
typedescription_t whose fieldName is a `const char*` must produce such a
reference, so one of these is true:

  (a) field names are stored as 32-bit RVAs (or offsets into a pool),
  (b) the field tables live in the uninitialised tail of .data and are built at
      runtime by constructors,
  (c) the m_iHealth string used by the datamap is not one of the .rdata copies.

This script answers (a)/(b) empirically and, if name-pointers do exist, derives
the real entry stride and field positions from the layout of the table itself.

Output: temp/dm2.txt
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


# ---------------------------------------------------------------------------
# PE
# ---------------------------------------------------------------------------
e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
image_base = struct.unpack_from("<Q", data, e_lfanew + 0x18 + 0x18)[0]
nsec = struct.unpack_from("<H", data, e_lfanew + 6)[0]
opt_size = struct.unpack_from("<H", data, e_lfanew + 0x14)[0]
sec_tab = e_lfanew + 0x18 + opt_size
SEC = []
for i in range(nsec):
    o = sec_tab + 0x28 * i
    name = data[o:o + 8].rstrip(b"\x00").decode("latin1")
    vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, o + 8)
    SEC.append((name, va, vsize, rawptr, rawsize))

p("# datamap forensics 2")
p("imagebase %#x  file %d bytes" % (image_base, len(data)))
for name, va, vsize, rawptr, rawsize in SEC:
    p("  %-9s va=%#010x vsize=%#010x rawptr=%#010x rawsize=%#010x  raw-backed rva end=%#x"
      % (name, va, vsize, rawptr, rawsize, va + rawsize))


def rva2off(rva):
    for name, va, vsize, rawptr, rawsize in SEC:
        if va <= rva < va + max(vsize, rawsize):
            d = rva - va
            return rawptr + d if d < rawsize else None
    return None


def off2rva(off):
    for name, va, vsize, rawptr, rawsize in SEC:
        if rawptr <= off < rawptr + rawsize:
            return va + (off - rawptr)
    return None


def rd(rva, n):
    o = rva2off(rva)
    return None if o is None else data[o:o + n]


def cstr(rva, n=96):
    b = rd(rva, n)
    if not b:
        return None
    z = b.find(b"\x00")
    if z <= 0:
        return None
    try:
        s = b[:z].decode("latin1")
    except UnicodeDecodeError:
        return None
    return s


def is_ident(s):
    return bool(s) and len(s) >= 3 and all(c.isalnum() or c == "_" for c in s)


# ---------------------------------------------------------------------------
# 1. Every absolute qword in .rdata/.data that points at an identifier string.
#    This is what a `const char* fieldName` / `dataClassName` must look like.
# ---------------------------------------------------------------------------
p("")
p("## qword references to identifier strings")

ident_by_va = {}
for name, va, vsize, rawptr, rawsize in SEC:
    if name not in (".rdata", ".data", "_RDATA", ".ooa"):
        continue
    blob = data[rawptr:rawptr + rawsize]
    lo = min(vsize, rawsize)
    i = blob.find(b"\x00")
    while 0 < i < lo - 4:
        j = blob.find(b"\x00", i + 1)
        if j < 0:
            break
        s = blob[i + 1:j]
        if 3 <= len(s) <= 96 and s[:1].isalpha() and all(32 < c < 127 for c in s):
            try:
                txt = s.decode("latin1")
            except UnicodeDecodeError:
                txt = ""
            if is_ident(txt):
                ident_by_va[va + i + 1] = txt
        i = j
p("  identifier strings found: %d" % len(ident_by_va))
if ident_by_va:
    kv = sorted(ident_by_va)
    p("  sample: %s" % [ident_by_va[k] for k in kv[:12]])

ident_va_set = set(ident_by_va)

# collect (slot_rva, string_rva) for aligned qwords holding image_base + ident
refs = []
for name, va, vsize, rawptr, rawsize in SEC:
    if name not in (".rdata", ".data"):
        continue
    blob = data[rawptr:rawptr + rawsize]
    n = len(blob) - len(blob) % 8
    for off in range(0, n, 8):
        q = struct.unpack_from("<Q", blob, off)[0]
        if q < image_base:
            continue
        t = q - image_base
        if t in ident_va_set:
            refs.append((va + off, t))
p("  aligned qword refs to those strings: %d" % len(refs))
if refs:
    refs.sort()
    gap = Counter(b[0] - a[0] for a, b in zip(refs, refs[1:]))
    p("  top gaps between consecutive refs:")
    for g, c in gap.most_common(12):
        p("    gap %#06x : %d" % (g, c))
    for stride in [g for g, c in gap.most_common(6) if 8 <= g <= 0x400]:
        seq = [(a, b) for a, b in zip(refs, refs[1:]) if b[0] - a[0] == stride]
        p("")
        p("  --- stride %#x : %d pairs, %d distinct names ---"
          % (stride, len(seq), len({ident_by_va[b[1]] for _, b in seq})))
        for a, b in seq[:6]:
            p("    slot %#010x name@string %#x %r" % (a[0], a[1], ident_by_va[a[1]]))
            for delta in (8, 0x10, 0x18, 0x1C, 0x20):
                o2 = rva2off(a[0] + delta)
                if o2 is None:
                    continue
                v = struct.unpack_from("<I", data, o2)[0]
                p("       +%#04x u32=%#x" % (delta, v))


# ---------------------------------------------------------------------------
# 2. 32-bit reference test for field names that have no qword ref.
# ---------------------------------------------------------------------------
p("")
p("## 32-bit reference test")
for probe in ("m_iHealth", "m_iTeamNum", "m_vecOrigin", "m_currentFrame"):
    pat = probe.encode()
    occ, pos = [], data.find(pat)
    while pos != -1:
        if pos == 0 or data[pos - 1] == 0:
            occ.append(pos)
        pos = data.find(pat, pos + 1)
    p("  %-14s whole-string occurrences: %s" % (probe, [hex(o) for o in occ[:6]]))
    for o in occ[:3]:
        rva = off2rva(o)
        if rva is None:
            continue
        pat_q = struct.pack("<Q", image_base + rva)
        pat_d = struct.pack("<I", rva)
        qhits, pos = [], data.find(pat_q)
        while pos != -1:
            if off2rva(pos) is not None:
                qhits.append(off2rva(pos))
            pos = data.find(pat_q, pos + 1)
        dhits, pos = [], data.find(pat_d)
        while pos != -1:
            if off2rva(pos) is not None:
                dhits.append(off2rva(pos))
            pos = data.find(pat_d, pos + 1)
        p("    rva %#010x  qword-refs=%s  u32-refs=%s"
          % (rva, [hex(x) for x in qhits[:6]], [hex(x) for x in dhits[:6]]))

# ---------------------------------------------------------------------------
# 3. The C_BaseEntity cluster: dump it as 0x40 records so the record shape is
#    read off real bytes instead of assumed.
# ---------------------------------------------------------------------------
p("")
p("## C_BaseEntity table neighbourhood (0x40 records)")
for i in range(24):
    r = 0x3354b20 + 0x40 * i
    o = rva2off(r)
    if o is None:
        p("  %#010x  <not raw-backed>" % r)
        continue
    q0, q1 = struct.unpack_from("<QQ", data, o)
    nm = cstr(q0 - image_base) if q0 > image_base else None
    nm1 = cstr(q1 - image_base) if q1 > image_base else None
    u32s = struct.unpack_from("<8I", data, o)
    p("  %#010x  q0=%#x %-22r q1=%#x %-22r dwords=%s"
      % (r, q0, nm, q1, nm1, " ".join("%x" % v for v in u32s)))

# 4. Are there *any* name-pointer tables at all?  Print the densest run.
p("")
p("## densest run of name-pointer slots")
best = None
cur = [refs[0]] if refs else []
for a, b in zip(refs, refs[1:]):
    if b[0] - a[0] <= 0x100:
        cur.append(b)
    else:
        if best is None or len(cur) > len(best):
            best = cur
        cur = [b]
if best is None or len(cur) > len(best):
    best = cur
if best:
    p("  run start %#010x len %d span %#x" % (best[0][0], len(best),
                                              best[-1][0] - best[0][0]))
    for slot, s in best[:30]:
        p("    %#010x %r" % (slot, ident_by_va[s]))

with open(os.path.join(HERE, "dm2.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
print("[written] temp/dm2.txt (%d lines)" % len(out))

