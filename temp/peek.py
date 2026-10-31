"""peek.py -- hexdump a virtual address out of the on-disk image.

The typedescription arrays that dm32 rebuilds from initialiser store streams
live in .data; if the linker emitted their image bytes then this dump is the
ground truth to diff against.  Zero bytes mean the region is BSS-like and the
store stream really is the only source of values.
"""
import struct
import sys

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"

with open(PATH, "rb") as fh:
    raw = fh.read()

e_lfanew = struct.unpack_from("<I", raw, 0x3C)[0]
nsec = struct.unpack_from("<H", raw, e_lfanew + 6)[0]
opt = e_lfanew + 24
base = struct.unpack_from("<Q", raw, opt + 24)[0]
secs = []
for i in range(nsec):
    o = opt + struct.unpack_from("<H", raw, e_lfanew + 20)[0] + i * 40
    name = raw[o:o + 8].rstrip(b"\0").decode("latin-1")
    vsize, va, rsize, rptr = struct.unpack_from("<IIII", raw, o + 8)
    secs.append((name, base + va, vsize, rsize, rptr))


def off_of(va):
    for name, sva, vsize, rsize, rptr in secs:
        if sva <= va < sva + max(vsize, rsize):
            delta = va - sva
            return (name, rptr + delta) if delta < rsize else (name, None)
    return (None, None)


def cstr(va):
    name, off = off_of(va)
    if off is None:
        return None
    end = raw.find(b"\0", off)
    return raw[off:end].decode("latin-1", "replace")


def main():
    va = int(sys.argv[1], 16)
    n = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0x68
    name, off = off_of(va)
    print("va=%#x section=%s file_off=%s" % (va, name, off))
    if off is None:
        return
    for i in range(0, n, 16):
        chunk = raw[off + i:off + i + 16]
        print("  %#012x  %s  |%s|" % (va + i, chunk.hex(" "),
                                      "".join(chr(c) if 32 <= c < 127 else "."
                                              for c in chunk)))
    # annotate one typedescription record
    if n >= 0x68:
        t, o, _, sz = struct.unpack_from("<IIII", raw, off)
        flags = struct.unpack_from("<i", raw, off + 0x14)[0]
        td, nm, sr = struct.unpack_from("<QQQ", raw, off + 0x20)
        alt = struct.unpack_from("<Q", raw, off + 0x60)[0]
        print("  record: type=%d off=%#x size=%d flags=%#x" % (t, o, sz, flags))
        print("          td=%#x name=%r sr=%#x alt=%#x -> %r"
              % (td, cstr(nm), sr, alt, cstr(alt) if alt else None))


main()
