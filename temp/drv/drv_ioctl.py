"""drv_ioctl.py -- pull the *real* IOCTL codes out of gdrv3.sys and MsIo64.sys.

The dispatch routine compares IRP->Tail.Overlay.CurrentStackLocation->
Parameters.DeviceIoControl.IoControlCode against immediates.  In x64 that
comparison is one of:

    81 7B 18 <imm32>     cmp dword [rbx+18h], imm32   (rbx = IRP stack loc)
    81 7D ?? <imm32>     cmp dword [rbp+disp8], imm32
    81 79 18 <imm32>     cmp dword [rcx+18h], imm32
    81 F8 / 81 FB <imm32> cmp eax/ebx, imm32
    3D <imm32>           cmp eax, imm32

So: walk the .text, decode 0x81 / 0x3D forms, keep only immediates with the
device bit set (>= 0x80000000).  That turns 4791 false positives into the
handful of codes the driver actually tests.
"""
import os
import re
import struct
import sys

DRV = os.path.join(os.environ["SystemRoot"], "System32", "drivers")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "drv_ioctl.txt")


def pe_text(buf):
    """Return (text_rva, text_off, text_size) for the first .text section."""
    e_lfanew = struct.unpack_from("<I", buf, 0x3C)[0]
    nsec = struct.unpack_from("<H", buf, e_lfanew + 6)[0]
    opt = struct.unpack_from("<H", buf, e_lfanew + 20)[0]
    sec = e_lfanew + 24 + opt
    for i in range(nsec):
        o = sec + i * 40
        name = buf[o:o + 8].rstrip(b"\x00").decode("ascii", "replace")
        vsize, vaddr, rsize, raddr = struct.unpack_from("<IIII", buf, o + 8)
        if name == ".text":
            return vaddr, raddr, max(vsize, rsize)
    return None, None, None


def imm32s(code):
    """Yield (offset, imm) for cmp-immediate instructions in the blob."""
    out = []
    i = 0
    n = len(code)
    while i < n - 6:
        b = code[i]
        if b == 0x81:
            modrm = code[i + 1]
            reg = (modrm >> 3) & 7
            mod = modrm >> 6
            if reg == 7:                                  # cmp r/m32, imm32
                if mod == 3:                              # cmp r32, imm32
                    imm = struct.unpack_from("<I", code, i + 2)[0]
                    out.append((i, imm)); i += 6; continue
                if code[i + 2] in (0x18, 0x10, 0x20, 0x08, 0x00) or True:
                    imm = struct.unpack_from("<I", code, i + 2 + (1 if mod == 1 else 0) if mod == 1 else i + 3)[0]
                    out.append((i, imm)); i += 7 if mod != 1 else 6; continue
        elif b == 0x3D:                                   # cmp eax, imm32
            imm = struct.unpack_from("<I", code, i + 1)[0]
            out.append((i, imm)); i += 5; continue
        i += 1
    return out


def analyze(name):
    path = os.path.join(DRV, name)
    buf = open(path, "rb").read()
    rva, off, size = pe_text(buf)
    lines = ["", "=" * 68, "%s  .text rva=%#x off=%#x size=%#x" % (name, rva, off, size), "=" * 68]
    code = buf[off:off + size]
    hits = {}
    for o, imm in imm32s(code):
        if imm < 0x80000000:
            continue
        # keep only values that look like a CTL_CODE: method in low 2 bits,
        # function in 0x800..0xfff, device type >= 0x8000
        if not (0x800 <= ((imm >> 2) & 0xFFF) <= 0xFFF):
            continue
        if ((imm >> 16) & 0xFFFF) < 0x8000:
            continue
        hits.setdefault(imm, []).append(rva + o)
    lines.append("%d distinct candidate codes" % len(hits))
    for v in sorted(hits):
        lines.append("  %#010x   referenced at %s" % (v, ", ".join("%#x" % a for a in hits[v][:6])))
    return lines


def main():
    lines = []
    for n in ("gdrv3.sys", "MsIo64.sys"):
        p = os.path.join(DRV, n)
        lines += analyze(n) if os.path.exists(p) else ["MISSING " + p]
    text = "\n".join(lines) + "\n"
    open(OUT, "w", encoding="utf-8").write(text)
    sys.stdout.write(text)


main()
