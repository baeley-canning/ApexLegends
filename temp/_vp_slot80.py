#!/usr/bin/env python3
"""Decode the fast path at 0x20DB0BE (vtable+0x80 body) -- which buffer is current."""
from __future__ import annotations

import struct

import capstone
import pefile

EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
OUT = r"C:\Users\New User\OneDrive\Desktop\cheating\temp\\_vp_slot80_out.txt"


def main() -> int:
    pe = pefile.PE(EXE, fast_load=True)
    data = open(EXE, "rb").read()
    text = pe.sections[0]
    t_off, t_rva = text.PointerToRawData, text.VirtualAddress
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = False
    md.skipdata = True
    L: list[str] = []
    for start, n, title in ((0x20DB0BE, 0x120, "slot+0x80 fast path"),
                            (0x20DB3A0, 0x30, "slot+0x88"),
                            (0x20DB3C0, 0x30, "slot+0x70")):
        L.append(f"=== {title} 0x{start:X} ===")
        off = t_off + (start - t_rva)
        for addr, size, mnem, ops in md.disasm_lite(data[off:off + n], start):
            note = ""
            if "rip +" in ops:
                d = int(ops.split("[rip + ")[1].split("]")[0], 16)
                note = f"   ; -> 0x{addr + size + d:X}"
            L.append(f"  {addr:08X}  {mnem:<10} {ops}{note}")
        L.append("")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")
    print(f"wrote {OUT}: {len(L)} lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
