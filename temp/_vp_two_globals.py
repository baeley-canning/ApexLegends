#!/usr/bin/env python3
"""One-pass disambiguation of the two candidate globals around 0x5267000.

G1 = 0x5267B70 (read by 0x20B7FD0, the world-to-screen consumer)
G2 = 0x5263B70 (written by the function that stores the 0x22670F0 result)
Read-only.  Writes temp\\_vp_two_globals_out.txt.
"""
from __future__ import annotations

import bisect
import struct

import capstone
import pefile

EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
OUT = r"C:\Users\New User\OneDrive\Desktop\cheating\temp\\_vp_two_globals_out.txt"
G1, G2 = 0x5267B70, 0x5263B70
STRS = (0x30EE7F8, 0x30EF1A0, 0x30EF1D7, 0x30EF5F8)
BODIES = ((0x20B7FD0, 0xF4, "world-to-screen (G1 consumer)"),
          (0x20B8A15, 0x100, "G2 writer / assert path"),
          (0x20DB0BE, 0x20, "indexed +0x11A390 reader"),
          (0x226E750, 0x80, "pointer-pair swap A"))


def main() -> int:
    pe = pefile.PE(EXE, fast_load=True)
    data = open(EXE, "rb").read()
    base = pe.OPTIONAL_HEADER.ImageBase
    text = pe.sections[0]
    t_off, t_sz, t_rva = text.PointerToRawData, text.Misc_VirtualSize, text.VirtualAddress
    pdata = next(s for s in pe.sections if s.Name.startswith(b".pdata"))

    funcs = []
    for i in range(0, pdata.Misc_VirtualSize - 11, 12):
        b, e, _u = struct.unpack_from("<III", data, pdata.PointerToRawData + i)
        if b and e > b and t_rva <= b < t_rva + t_sz:
            funcs.append((b, min(e, t_rva + t_sz)))
    funcs.sort()
    fstarts = [b for b, _ in funcs]

    def func_of(rva: int) -> tuple[int, int]:
        i = bisect.bisect_right(fstarts, rva) - 1
        if i >= 0 and funcs[i][0] <= rva < funcs[i][1]:
            return funcs[i]
        return (0, 0)

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = False
    md.skipdata = True

    refs = {G1: [], G2: []}
    strrefs: dict[int, list[tuple[int, str]]] = {s: [] for s in STRS}
    for b, e in funcs:
        off = t_off + (b - t_rva)
        for addr, size, mnem, ops in md.disasm_lite(data[off:off + (e - b)], b):
            if "rip" not in ops:
                continue
            try:
                if "[rip + " in ops:
                    disp = int(ops.split("[rip + ")[1].split("]")[0], 16)
                elif "[rip - " in ops:
                    disp = -int(ops.split("[rip - ")[1].split("]")[0], 16)
                else:
                    continue
            except (IndexError, ValueError):
                continue
            tgt = addr + size + disp
            if tgt in refs:
                refs[tgt].append((addr, mnem, ops))
            if mnem == "lea" and tgt in strrefs:
                strrefs[tgt].append((addr, hex(b)))

    L: list[str] = []
    def p(s: str = "") -> None:
        L.append(s)

    for g in (G1, G2):
        p(f"=== global 0x{g:X}: {len(refs[g])} refs ===")
        for addr, mnem, ops in refs[g]:
            fb, fe = func_of(addr)
            d = "A" if mnem == "lea" else ("W" if ops[0] in "qdb" and "ptr [rip" in ops else "R")
            p(f"  {d} 0x{addr:X}  {mnem:<8} {ops}   [func 0x{fb:X}..0x{fe:X}]")
        p("")

    p("=== string lea-refs ===")
    for s in STRS:
        p(f"  0x{s:X}: {len(strrefs[s])} " + ", ".join(f"0x{a:X}@0x{b}" for a, b in strrefs[s]))
    p("")

    for start, n, title in BODIES:
        p(f"=== {title} 0x{start:X} ===")
        off = t_off + (start - t_rva)
        for addr, size, mnem, ops in md.disasm_lite(data[off:off + n], start):
            p(f"  {addr:08X}  {mnem:<10} {ops}")
        p("")

    def rva2off(r: int) -> int | None:
        for s2 in pe.sections:
            if s2.VirtualAddress <= r < s2.VirtualAddress + s2.SizeOfRawData:
                return s2.PointerToRawData + (r - s2.VirtualAddress)
        return None
    p("=== global slots in the file (initial image) ===")
    for g in (G1, G2):
        off = rva2off(g)
        p(f"  0x{g:X}: " + ("<bss>" if off is None else data[off:off + 8].hex(" ")))

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")
    print(f"wrote {OUT}: {len(L)} lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
