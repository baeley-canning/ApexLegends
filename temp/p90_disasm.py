r"""p90_disasm.py -- disassemble gdrv3.sys around the crash RIP offset.

The 0x3B bugcheck from today's four runs all faulted at
    gdrv3 + 0x2e81   (0xC0000005, in a system service call)
i.e. the same driver instruction while the device handle was being closed.
0x2e81 is an RVA inside the image; this maps it to a file offset through the
section table and prints the bytes around it, so the dereference that faults is
visible instead of guessed.

Read-only: opens the .sys for reading, never loads it.
Usage: python temp\p90_disasm.py [rva] [before] [after]
"""
import os
import struct
import sys

from capstone import Cs, CS_ARCH_X86, CS_MODE_64

SYS = os.environ.get("GDRV3",
                     r"C:\Windows\System32\drivers\gdrv3.sys")
RVA = int(sys.argv[1], 0) if len(sys.argv) > 1 else 0x2E81
BEFORE = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x30
AFTER = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x30


def sections(b):
    e_lfanew = struct.unpack_from("<I", b, 0x3C)[0]
    if b[e_lfanew:e_lfanew + 4] != b"PE\0\0":
        raise SystemExit("not a PE")
    nsec = struct.unpack_from("<H", b, e_lfanew + 6)[0]
    optsz = struct.unpack_from("<H", b, e_lfanew + 20)[0]
    opt = e_lfanew + 24
    image_base = struct.unpack_from("<Q", b, opt + 24)[0]
    magic = struct.unpack_from("<H", b, opt)[0]
    tbl = opt + optsz
    out = []
    for i in range(nsec):
        o = tbl + 40 * i
        name = b[o:o + 8].rstrip(b"\0").decode("latin-1")
        vsz, va, rsz, raw = struct.unpack_from("<IIII", b, o + 8)
        out.append((name, vsz, va, rsz, raw))
    return magic, image_base, out


def main():
    b = open(SYS, "rb").read()
    magic, image_base, secs = sections(b)
    print("file      %s  %d B" % (SYS, len(b)))
    print("machine64 magic=%#x image_base=%#x" % (magic, image_base))
    hit = None
    for name, vsz, va, rsz, raw in secs:
        print("  sec %-8s va=%#010x vsz=%#x rsz=%#x raw=%#x" % (name, va, vsz, rsz, raw))
        span = max(vsz, rsz)
        if va <= RVA < va + span:
            hit = (name, va, raw)
    if not hit:
        raise SystemExit("rva %#x is not inside any section" % RVA)
    name, va, raw = hit
    off = RVA - va + raw
    print("rva %#x -> section %s file offset %#x" % (RVA, name, off))

    md = Cs(CS_ARCH_X86, CS_MODE_64)
    start = off - BEFORE
    chunk = b[start:off + AFTER]
    for ins in md.disasm(chunk, RVA - BEFORE):
        mark = "  <<< FAULT" if ins.address == RVA else ""
        print("%#08x %-16s %-8s %s%s"
              % (ins.address, ins.bytes.hex(), ins.mnemonic, ins.op_str, mark))
    return 0


if __name__ == "__main__":
    sys.exit(main())
