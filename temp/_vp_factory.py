#!/usr/bin/env python3
"""What does 0x22670F0 return (the object cached at 0x5267B70)?

Dumps the factory body, the pdata entries around it, and the assertion strings.
Read-only.  Writes temp\\_vp_factory_out.txt.
"""
from __future__ import annotations

import struct

import capstone
import pefile

EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
OUT = r"C:\Users\New User\OneDrive\Desktop\cheating\temp\\_vp_factory_out.txt"
FACTORY = 0x22670F0
CONT = 0x2267625
STRINGS = (0x30EF1A0, 0x30EF1D7, 0x30EF5F8, 0x30EE7F8)


def main() -> int:
    pe = pefile.PE(EXE, fast_load=True)
    data = open(EXE, "rb").read()
    base = pe.OPTIONAL_HEADER.ImageBase
    text = pe.sections[0]
    t_off, t_rva = text.PointerToRawData, text.VirtualAddress
    pdata = next(s for s in pe.sections if s.Name.startswith(b".pdata"))

    entries = []
    for i in range(0, pdata.Misc_VirtualSize - 11, 12):
        b, e, _u = struct.unpack_from("<III", data, pdata.PointerToRawData + i)
        if b and e > b:
            entries.append((b, e))
    entries.sort()

    L: list[str] = []
    def p(s: str = "") -> None:
        L.append(s)

    p("=== pdata entries near the factory ===")
    for b, e in entries:
        if 0x2266E00 <= b <= 0x2267900:
            p(f"  0x{b:X}..0x{e:X} size=0x{e-b:X}")

    def cstr(rva: int) -> str:
        for s in pe.sections:
            if s.VirtualAddress <= rva < s.VirtualAddress + s.SizeOfRawData:
                o = s.PointerToRawData + (rva - s.VirtualAddress)
                z = data.find(b"\x00", o, o + 200)
                return data[o:z].decode("ascii", "replace")
        return "<n/a>"

    p("")
    p("=== strings ===")
    for r in STRINGS:
        p(f"  0x{r:X}: {cstr(r)!r}")

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = False
    md.skipdata = True
    p("")
    p(f"=== factory body 0x{FACTORY:X} (0x400 bytes) ===")
    off = t_off + (FACTORY - t_rva)
    for addr, size, mnem, ops in md.disasm_lite(data[off:off + 0x400], FACTORY):
        note = ""
        if mnem == "lea" and "rip +" in ops:
            d = int(ops.split("[rip + ")[1].split("]")[0], 16)
            note = f"   ; -> 0x{addr + size + d:X}"
        p(f"  {addr:08X}  {mnem:<10} {ops}{note}")

    p("")
    p(f"=== continuation 0x{CONT:X} (0x180 bytes) ===")
    off = t_off + (CONT - t_rva)
    for addr, size, mnem, ops in md.disasm_lite(data[off:off + 0x180], CONT):
        note = ""
        if mnem == "lea" and "rip +" in ops:
            d = int(ops.split("[rip + ")[1].split("]")[0], 16)
            note = f"   ; -> 0x{addr + size + d:X}"
        p(f"  {addr:08X}  {mnem:<10} {ops}{note}")

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")
    print(f"wrote {OUT}: {len(L)} lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
