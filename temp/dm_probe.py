"""Ground-truth probe for MSVC datamap_t / typedescription_t layout.

We know the class/field name strings exist in .rdata (probe_pe.txt), so instead
of guessing the layout we locate every qword that points at "m_iHealth" /
"C_BaseEntity" and dump the surrounding bytes.  From that we can read off the
real field size, the type/offset/name positions and the datamap_t header.
"""
import struct
import sys

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
data = open(PATH, "rb").read()

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


def u64(rva):
    b = rd(rva, 8)
    return None if not b or len(b) < 8 else struct.unpack("<Q", b)[0]


def u32(rva):
    b = rd(rva, 4)
    return None if not b or len(b) < 4 else struct.unpack("<I", b)[0]


def i32(rva):
    b = rd(rva, 4)
    return None if not b or len(b) < 4 else struct.unpack("<i", b)[0]


def cstr(rva, n=200):
    b = rd(rva, n)
    if not b:
        return None
    z = b.find(b"\x00")
    if z < 0:
        return None
    try:
        return b[:z].decode("latin1")
    except UnicodeDecodeError:
        return None


def find_qword_refs(va):
    """every aligned qword equal to va -> (section, rva of the qword)"""
    pat = struct.pack("<Q", va)
    out, pos = [], data.find(pat)
    while pos != -1:
        if pos % 8 == 0:
            rva = off2rva(pos)
            if rva is not None:
                out.append(rva)
        pos = data.find(pat, pos + 1)
    return out


def hexdump(rva, n=0x90):
    b = rd(rva, n) or b""
    lines = []
    for i in range(0, len(b) - len(b) % 16, 16):
        chunk = b[i:i + 16]
        txt = "".join(chr(c) if 32 <= c < 127 else "." for c in chunk)
        lines.append("  +0x%04x  %-64s %s" % (i, " ".join(
            "%08x" % struct.unpack_from("<I", chunk, j)[0] for j in range(0, 16, 4)), txt))
    return lines


def probe_name(label):
    print("=" * 78)
    print("%s" % label)
    pat = label.encode()
    occ, pos = [], data.find(pat)
    while pos != -1:
        # only accept "whole string" starts: NUL right before the name
        if pos == 0 or data[pos - 1] == 0:
            occ.append(pos)
        pos = data.find(pat, pos + 1)
    print("  whole-string occurrences: %d -> %s" % (len(occ), [hex(o) for o in occ[:8]]))
    for off in occ[:6]:
        va = image_base + off2rva(off)
        refs = find_qword_refs(va)
        print("  @off %#x rva %#x va %#x refs=%s" % (off, off2rva(off), va, [hex(r) for r in refs[:8]]))
        for r in refs[:4]:
            print("\n  --- typedescription_t candidate, name field at %#x ---" % r)
            for ln in hexdump(r - 0x10, 0x90):
                print(ln)
            print("     type=%d/%#x name=%r off=%#x td=%#x size=%#x" % (
                i32(r - 8) or -1, u32(r - 8) or 0, cstr(r), u32(r + 8) or 0,
                u64(r + 0x40) or 0, u32(r + 0x48) or 0))
    return occ


probe_name("m_iHealth")
probe_name("C_BaseEntity")
