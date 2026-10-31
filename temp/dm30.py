"""dm30: inspect the runtime image cache and read the datamap_t / arrays.

dm24 proved the record template but attributed fields to classes heuristically
(dt_leas inside the same initializer).  The real attribution is available: the
client-class descriptor holds a `datamap_t*` at +0x18, and a datamap_t holds

    +0x00  DataMapField *dataDesc      -> the 0x68-stride record array
    +0x08  int           dataNumFields
    +0x10  char         *dataClassName ("DT_*")
    +0x18  datamap_t    *baseMap

This dumps the cached runtime .data for every piece of that chain and
disassembles the C_AI_BaseNPC initializer (0x1420d8e70) with real registers.

Usage: python dm30.py   ->  temp/dm30.txt
"""
import os
import pickle
import struct

import capstone
import pefile

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
IMGBASE = 0x140000000
STRIDE = 0x68

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


def secname(va):
    s = sec_of(va)
    return "?" if s is None else "%s+%#x" % (s[0], va - s[1])


def cstr_file(va, n=96):
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


with open(os.path.join(HERE, "dm11_cache.pkl"), "rb") as fh:
    C = pickle.load(fh)
img, funcs, ident, dt_leas = C["img"], C["funcs"], C["ident"], C["dt_leas"]
p("=" * 92)
p("## cache")
p("=" * 92)
p("  keys      : %s" % sorted(C.keys()))
p("  img bytes : %d  (va range %#x .. %#x)" % (len(img), min(img), max(img)))
p("  funcs     : %d   dt_leas: %d   ident: %d"
  % (len(funcs), len(dt_leas), len(ident)))


def get(va, n):
    b = bytearray()
    for k in range(n):
        v = img.get(va + k)
        if v is None:
            return None
        b.append(v)
    return bytes(b)


def u32(va):
    b = get(va, 4)
    return None if b is None else struct.unpack("<I", b)[0]


def i32(va):
    b = get(va, 4)
    return None if b is None else struct.unpack("<i", b)[0]


def u64(va):
    b = get(va, 8)
    return None if b is None else struct.unpack("<Q", b)[0]


def dump(va, n=0x40, label=""):
    p("")
    p("## cache @ %#x  %s  (%s)" % (va, label, secname(va)))
    for d in range(0, n, 8):
        v = u64(va + d)
        if v is None:
            p("    +0x%03x  <unreadable>" % d)
            continue
        if v == 0:
            tag = "0"
        elif v < 0x100000000:
            tag = "%#x / i32 %d,%d" % (v, i32(va + d), i32(va + d + 4))
        else:
            s = ident.get(v) or cstr_file(v)
            tag = "%s%s" % (secname(v), ("  '%s'" % s) if s else "")
        p("    +0x%03x  %016x  %s" % (d, v, tag))


dump(0x143d18f80, 0x30, "client-class descriptor (C_AI_BaseNPC)")
dump(0x143d25200, 0x30, "datamap_t? (dm28 +0x18 target)")
for va in (0x14e6d1160, 0x14e699140, 0x14e6d1160 - STRIDE,
           0x14e6d1160 + 0x68 * 16):
    dump(va, 0x70, "array region")


def record(va):
    t, ofs = u32(va), u32(va + 4)
    size, fl, ext = u32(va + 0xc), u32(va + 0x14), u64(va + 0x18)
    nm = u64(va + 0x28)
    if None in (t, ofs, size, fl, nm) or not nm:
        return None
    name = ident.get(nm) or cstr_file(nm)
    if not name or not (name[0].isalpha() or name[0] == "_"):
        return None
    if not all(c.isalnum() or c == "_" for c in name):
        return None
    return {"type": t, "off": ofs, "size": size, "flags": fl, "name": name,
            "extra": ext, "a58": i32(va + 0x58), "a5c": i32(va + 0x5c),
            "a08": u32(va + 8), "fn": u64(va + 0x48)}


def walk(array_va, limit=300):
    p("")
    p("=" * 92)
    p("## record walk %#x (stride 0x68)" % array_va)
    p("=" * 92)
    n = 0
    va = array_va
    while n < limit:
        r = record(va)
        if r is None:
            p("  stop at slot %d (%#x)" % (n, va))
            break
        p("  [%3d] %#x type=%-2d off=%-8s size=%-3d fl=%#04x ex=%#x %-30s"
          % (n, va, r["type"], hex(r["off"]), r["size"], r["flags"],
             r["extra"], r["name"]))
        if (r["a58"], r["a5c"]) != (-1, 1):
            p("        !! tail %d,%d a08=%#x" % (r["a58"], r["a5c"], r["a08"]))
        va += STRIDE
        n += 1
    p("  -> %d records" % n)
    return n


walk(0x14e6d1160)
walk(0x14e699140)

md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = True


def dis(lo, hi):
    p("")
    p("=" * 92)
    p("## disasm %#x .. %#x" % (lo, hi))
    p("=" * 92)
    s = sec_of(lo)
    off = s[4] + (lo - s[1])
    for ins in md.disasm(raw[off:off + (hi - lo)], lo):
        note = ""
        for op in ins.operands:
            if op.type == capstone.x86.X86_OP_MEM:
                if op.mem.base == capstone.x86.X86_REG_RIP:
                    t = ins.address + ins.size + op.mem.disp
                    note += "   -> %#x %s" % (t, secname(t))
                    st = cstr_file(t)
                    if st:
                        note += " '%s'" % st
                elif op.mem.base:
                    note += "   -> [%s+%#x]" % (ins.reg_name(op.mem.base),
                                               op.mem.disp)
        p("  %#x  %-7s %-40s%s" % (ins.address, ins.mnemonic, ins.op_str,
                                   note))


dis(0x1420d98e0, 0x1420d9a90)

with open(os.path.join(HERE, "dm30.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
print("wrote dm30.txt (%d lines)" % len(out))
