import struct

try:
    import capstone
except ImportError:
    print("NO_CAPSTONE")
    raise SystemExit

b = open(r"C:\Windows\System32\drivers\gdrv3.sys", "rb").read()
secs = []
pe = struct.unpack_from("<I", b, 0x3C)[0]
n = struct.unpack_from("<H", b, pe + 6)[0]
opt = struct.unpack_from("<H", b, pe + 20)[0]
so = pe + 24 + opt
for i in range(n):
    o = so + 40 * i
    name = b[o:o + 8].rstrip(b"\x00").decode()
    vs, va, rs, ro = struct.unpack_from("<IIII", b, o + 8)
    secs.append((name, va, vs, ro, rs))


def rva2off(rva):
    for name, va, vs, ro, rs in secs:
        if va <= rva < va + max(vs, 1):
            return ro + (rva - va)
    return None


md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
md.detail = False

import io
import sys

import io

import io


def disasm_resilient(start, end):
    """Capstone stops at data bytes; resume at next byte on failure."""
    code = b[rva2off(start):rva2off(end)]
    out = []
    pos = 0
    va = start
    while pos < len(code):
        got = False
        for ins in md.disasm(code[pos:], va):
            out.append("%05x  %-22s %s %s" % (ins.address, ins.bytes.hex(),
                                              ins.mnemonic, ins.op_str))
            pos += ins.size
            va += ins.size
            got = True
        if not got:
            out.append("%05x  %02x            (db)" % (va, code[pos]))
            pos += 1
            va += 1
    return out


targets = [
    (0x2D84, 0x2E80, "worker 0x2019 MapMem_Phys_To_Linear2"),
    (0x33B0, 0x34C0, "worker 0x2584"),
    (0x3604, 0x3680, "worker 0x2014 read"),
    (0x3848, 0x39A0, "worker 0x2580"),
    (0x3AA0, 0x3BC0, "worker 0x2440"),
    (0xB0B0, 0xB200, "worker 0x2008 unmap"),
]
out = io.StringIO()
for start, end, title in targets:
    out.write("---- %s ----\n" % title)
    out.write("\n".join(disasm_resilient(start, end)))
    out.write("\n\n")
open(r"c:\Users\New User\OneDrive\Desktop\cheating\ext\page_workers.txt",
     "w").write(out.getvalue())
print("done")

out = io.StringIO()
for ins in md.disasm(b[rva2off(start):rva2off(end)], start):
    print("%05x  %-22s %s %s" % (ins.address, ins.bytes.hex(), ins.mnemonic,
                                 ins.op_str), file=out)
open(r"c:\Users\New User\OneDrive\Desktop\cheating\ext\page_workers.txt",
     "w").write(out.getvalue())
print("written", end - start, "bytes -> page_workers.txt")


