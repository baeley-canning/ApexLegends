"""dm29: validate the datamap layout directly against file bytes.

dm28 (ground-truth disassembly of three static initializers) settled the record
template:

    +0x00  dword  fieldType            (0x00..0x10, see dm24 cross-tab)
    +0x04  dword  fieldOffset          (written with a 8-byte store, +0x08 = 0)
    +0x0c  dword  fieldSize  (bytes)   (written with a 8-byte store, +0x10 = 0)
    +0x14  dword  flags
    +0x18  dword  0
    +0x20  qword  type descriptor (.data)
    +0x28  qword  fieldName    (internal, 'm_*')
    +0x48  qword  save/restore helper (.text) or 0
    +0x58  dword  -1
    +0x5c  dword  1
    +0x60  qword  external / networked name
    stride 0x68

This script answers the one remaining question: are those records present as
*bytes* in the file (so a plain scan suffices) or do they live in BSS and have
to be rebuilt from the initializers?  It prints the section table, maps every
anchor VA from dm28/dm24/dm25 into a section, and dumps the qwords around each
anchor so the datamap_t header can be identified.

Usage: python dm29.py
Output: temp/dm29.txt
"""
import os
import struct

import pefile

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
IMGBASE = 0x140000000

pe = pefile.PE(PATH, fast_load=True)
raw = open(PATH, "rb").read()
secs = [(s.Name.rstrip(b"\x00").decode("latin1"), IMGBASE + s.VirtualAddress,
         s.Misc_VirtualSize, s.SizeOfRawData, s.PointerToRawData)
        for s in pe.sections]

out = []


def p(s=""):
    out.append(s)
    print(s)


def sec_of(va):
    for s in secs:
        if s[1] <= va < s[1] + max(s[2], s[3]):
            return s
    return None


def off(va):
    """file offset of va, or None when the page is BSS (not backed by raw)"""
    s = sec_of(va)
    if s is None:
        return None
    d = va - s[1]
    if d >= s[3]:
        return None
    return s[4] + d


def u32(va):
    o = off(va)
    return None if o is None else struct.unpack_from("<I", raw, o)[0]


def u64(va):
    o = off(va)
    return None if o is None else struct.unpack_from("<Q", raw, o)[0]


def cstr(va, n=96):
    o = off(va)
    if o is None:
        return None
    e = raw.find(b"\x00", o, o + n)
    if e < 0:
        return None
    try:
        t = raw[o:e].decode("ascii")
    except UnicodeDecodeError:
        return None
    return t if t and all(32 <= ord(c) < 127 for c in t) else None


def secname(va):
    s = sec_of(va)
    return "?" if s is None else "%s+%#x%s" % (s[0], va - s[1],
                                                "" if off(va) else " (bss)")


p("=" * 92)
p("## sections")
p("=" * 92)
p("  %-10s %-14s %-12s %-12s %-10s" % ("name", "va", "vsize", "rawsize", "rawptr"))
for s in secs:
    p("  %-10s %#014x %#012x %#012x %#010x" % s)

p("")
p("=" * 92)
p("## anchor VAs")
p("=" * 92)
ANCHORS = [
    ("C_AI_BaseNPC field array (BSS?)", 0x14e6d1160),
    ("DT_HealthKit field array (BSS?)", 0x14e699140),
    ("DT_HealthKit datamap_t (dm25)", 0x143cdedd0),
    ("C_AI_BaseNPC datamap_t", 0x143d25200),
    ("C_AI_BaseNPC descriptor", 0x143d18f80),
    ("string in .data (dm28)", 0x143d27a8b),
    ("string in .data (dm28)", 0x143cfe8e0),
    ("type desc (dm28)", 0x143eb2570),
    ("type desc (dm28)", 0x143d14ac0),
]
for label, va in ANCHORS:
    p("  %#012x  %-40s %s" % (va, secname(va), label))


def dump(va, n=0x60, base=None):
    """dump n bytes at va as qwords with string / section annotation"""
    base = va if base is None else base
    o = off(va)
    if o is None:
        p("    <%#x not backed by raw data>" % va)
        return
    for d in range(0, n, 8):
        v = struct.unpack_from("<Q", raw, o + d)[0]
        d32 = struct.unpack_from("<II", raw, o + d)
        tag = ""
        if v == 0:
            tag = "0"
        elif v < 0x100000000:
            tag = "%#x / %d,%d" % (v, d32[0], d32[1])
        else:
            s = cstr(v)
            tag = "%s%s" % (secname(v), ("  '%s'" % s) if s else "")
        p("    +0x%03x  %016x  %s" % (d, v, tag))


p("")
p("=" * 92)
p("## dumps")
p("=" * 92)
for label, va in ANCHORS:
    p("")
    p("## %#x  %s   (base %#x)" % (va, label, va))
    dump(va, 0x50)


def rec(va):
    """read one 0x68-byte field record, or None when the slot is empty"""
    t, ofs = u32(va), u32(va + 4)
    size, flg = u32(va + 0xc), u32(va + 0x14)
    nm, ext = u64(va + 0x28), u64(va + 0x60)
    if t is None or ofs is None or size is None or nm is None:
        return None
    name = cstr(nm)
    if name is None:
        return None
    if not (name[0].isalpha() or name[0] == "_"):
        return None
    if not all(c.isalnum() or c == "_" for c in name):
        return None
    return {"type": t, "off": ofs, "size": size, "flags": flg, "name": name,
            "ext": cstr(ext) if ext else None,
            "tdesc": u64(va + 0x20), "fn": u64(va + 0x48),
            "a58": u32(va + 0x58), "a5c": u32(va + 0x5c),
            "a08": u32(va + 0x8), "a18": u32(va + 0x18)}


def walk(array_va, limit=512):
    p("")
    p("=" * 92)
    p("## array walk from %#x (stride 0x68)" % array_va)
    p("=" * 92)
    va = array_va
    n = 0
    while n < limit:
        r = rec(va)
        if r is None:
            p("  stop at %#x (slot empty)" % va)
            break
        p("  %#012x  type=%-2d off=%-6#x size=%-3d flags=%#04x  %-32s ext=%s"
          % (va, r["type"], r["off"], r["size"], r["flags"], r["name"],
             r["ext"]))
        if (r["a58"], r["a5c"]) != (0xffffffff, 1):
            p("     !! tail = %d,%d (expected -1,1)" % (r["a58"], r["a5c"]))
        if r["a08"] or r["a18"]:
            p("     !! +08=%#x +18=%#x" % (r["a08"], r["a18"]))
        va += 0x68
        n += 1
    p("  (%d records)" % n)
    return n


walk(0x14e6d1160)
walk(0x14e699140)

with open(os.path.join(HERE, "dm29.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
print("wrote dm29.txt (%d lines)" % len(out))
