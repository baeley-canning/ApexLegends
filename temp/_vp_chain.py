#!/usr/bin/env python3
"""Close the chain: static CViewRender object -> vtable -> slot +0x80 -> matrix field.

Everything here is read from the PE file only (no game, no heap, no driver).
Writes temp\\_vp_chain_out.txt.
"""
from __future__ import annotations

import struct

import capstone
import pefile

EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
OUT = r"C:\Users\New User\OneDrive\Desktop\cheating\temp\\_vp_chain_out.txt"
OBJ = 0x3D86100          # lea rax,[rip+0x1b1ead4] in GetViewRenderInstance fast path
SLOT = 0x80
NEAR = ((0x22675A2, 0x83), (0x22675E2, 0x43))


def main() -> int:
    pe = pefile.PE(EXE, fast_load=True)
    data = open(EXE, "rb").read()
    base = pe.OPTIONAL_HEADER.ImageBase
    secs = pe.sections

    L: list[str] = []
    def p(s: str = "") -> None:
        L.append(s)

    def rva2off(r: int) -> int | None:
        for s in secs:
            if s.VirtualAddress <= r < s.VirtualAddress + s.SizeOfRawData:
                return s.PointerToRawData + (r - s.VirtualAddress)
        return None

    def sec_of(r: int) -> str:
        for s in secs:
            if s.VirtualAddress <= r < s.VirtualAddress + s.Misc_VirtualSize:
                return s.Name.rstrip(b"\x00").decode()
        return "?"

    def q(r: int) -> int | None:
        o = rva2off(r)
        return None if o is None else struct.unpack_from("<Q", data, o)[0]

    p(f"=== static object 0x{OBJ:X} ({sec_of(OBJ)}) ===")
    vt = q(OBJ)
    if vt is None:
        p("  <bss - no initial vtable>")
        vt_rva = None
    else:
        vt_rva = vt - base if base <= vt < base + pe.OPTIONAL_HEADER.SizeOfImage else None
        p(f"  [obj+0x000] = 0x{vt:X} -> vtable rva 0x{(vt_rva or 0):X} ({sec_of(vt_rva) if vt_rva else '??'})")

    p("")
    p("=== first 0x40 qwords of the object (file init) ===")
    for i in range(0, 0x40, 8):
        val = q(OBJ + i)
        p(f"  +0x{i:02X} = " + ("<bss>" if val is None else f"0x{val:X}"))

    if vt_rva:
        p("")
        p(f"=== vtable 0x{vt_rva:X}: 24 slots ===")
        for i in range(24):
            v = q(vt_rva + i * 8)
            if v is None:
                p(f"  +0x{i*8:02X} <bss>")
                continue
            if base <= v < base + pe.OPTIONAL_HEADER.SizeOfImage:
                p(f"  +0x{i*8:02X} -> rva 0x{v-base:X} ({sec_of(v-base)})")
            else:
                p(f"  +0x{i*8:02X} -> 0x{v:X} (non-image)")

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = False
    md.skipdata = True

    if vt_rva:
        fn = q(vt_rva + SLOT)
        if fn and base <= fn < base + pe.OPTIONAL_HEADER.SizeOfImage:
            rva = fn - base
            p("")
            p(f"=== slot +0x{SLOT:X} function 0x{rva:X} ===")
            o = rva2off(rva)
            if o is None:
                p("  <not raw-backed>")
            else:
                for addr, size, mnem, ops in md.disasm_lite(data[o:o + 0x60], rva):
                    note = ""
                    if "rip +" in ops:
                        d = int(ops.split("[rip + ")[1].split("]")[0], 16)
                        note = f"   ; -> 0x{addr + size + d:X}"
                    p(f"  {addr:08X}  {mnem:<10} {ops}{note}")

    p("")
    p("=== factory tail paths ===")
    for start, n in NEAR:
        p(f"-- 0x{start:X}")
        o = rva2off(start)
        for addr, size, mnem, ops in md.disasm_lite(data[o:o + n], start):
            note = ""
            if "rip +" in ops:
                d = int(ops.split("[rip + ")[1].split("]")[0], 16)
                note = f"   ; -> 0x{addr + size + d:X}"
            p(f"  {addr:08X}  {mnem:<10} {ops}{note}")

    p("")
    p("=== derived chain ===")
    for off, name in ((0x11A390, "matrix ptr [0]"), (0x11A398, "matrix ptr [1]"),
                      (0x11A2D0, "matrix buffer A"), (0x11A310, "matrix buffer B")):
        p(f"  shape+0x{off:X} -> image rva 0x{OBJ + off:X} ({name})")

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")
    print(f"wrote {OUT}: {len(L)} lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
