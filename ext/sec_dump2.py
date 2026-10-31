import io
import struct

import capstone

b = open(r"C:\Windows\System32\drivers\MsIo64.sys", "rb").read()
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


def disasm_resilient(start, end):
    code = b[rva2off(start):rva2off(end)]
    res = []
    pos, va = 0, start
    while pos < len(code):
        got = False
        for ins in md.disasm(code[pos:], va):
            res.append("%05x  %-20s %s %s" % (ins.address, ins.bytes.hex(),
                                              ins.mnemonic, ins.op_str))
            pos += ins.size
            va += ins.size
            got = True
        if not got:
            res.append("%05x  %02x  (db)" % (va, code[pos]))
            pos += 1
            va += 1
    return res


out = io.StringIO()
out.write("---- INIT DriverEntry 0x5000-0x52b2 ----\n")
out.write("\n".join(disasm_resilient(0x5000, 0x52B2)))
out.write("\n\n---- rip-relative refs to .data 0x3150 ----\n")
for start, end in [(0x1000, 0x1F2F), (0x5000, 0x52B2)]:
    code = b[rva2off(start):rva2off(end)]
    pos, va = 0, start
    while pos < len(code):
        got = False
        for ins in md.disasm(code[pos:], va):
            pos += ins.size
            va += ins.size
            got = True
            if "rip +" in ins.op_str or "rip -" in ins.op_str:
                try:
                    rel = int(ins.op_str.split("rip ")[1].split("]")[0]
                              .replace(" ", ""), 16)
                except (ValueError, IndexError):
                    continue
                tgt = va + rel if "rip +" in ins.op_str else va - rel
                if tgt == 0x3150:
                    out.write("%05x  %s %s -> 0x3150\n"
                              % (ins.address, ins.mnemonic, ins.op_str))
        if not got:
            pos += 1
            va += 1
open(r"c:\Users\New User\OneDrive\Desktop\cheating\ext\msio_init.txt",
     "w").write(out.getvalue())
print("done", len(out.getvalue()))

