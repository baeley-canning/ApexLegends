#!/usr/bin/env python3
"""Locate every instruction touching the candidate view-matrix displacements.

Then check whether any small accessor function is referenced from a vtable, and
at which slot.  Read-only; writes temp\\_vp_acc_out.txt.
"""
from __future__ import annotations

import re
import struct

import capstone
import pefile

EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
OUT = r"C:\Users\New User\OneDrive\Desktop\cheating\temp\\_vp_acc_out.txt"
WANT = {0x11A390: "P0", 0x11A398: "P1", 0x11A2D0: "M0", 0x11A310: "M1",
        0x11A3A8: "f0", 0x11A2E0: "M0+10"}
SMALL = 0x60


def main() -> int:
    pe = pefile.PE(EXE, fast_load=True)
    data = open(EXE, "rb").read()
    base = pe.OPTIONAL_HEADER.ImageBase
    text = pe.sections[0]
    t_off, t_sz, t_rva = text.PointerToRawData, text.Misc_VirtualSize, text.VirtualAddress
    pdata = next(s for s in pe.sections if s.Name.startswith(b".pdata"))
    funcs = []
    for i in range(0, pdata.Misc_VirtualSize - 11, 12):
        b, e, u = struct.unpack_from("<III", data, pdata.PointerToRawData + i)
        if b and e > b and t_rva <= b < t_rva + t_sz:
            funcs.append((b, min(e, t_rva + t_sz)))
    funcs.sort()

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = False
    md.skipdata = True
    needle = re.compile(r"0x(11a390|11a398|11a2d0|11a310|11a3a8|11a2e0)\b", re.I)
    per_func: dict[tuple[int, int], list[tuple[int, str, str]]] = {}
    for b, e in funcs:
        off = t_off + (b - t_rva)
        for addr, size, mnem, ops in md.disasm_lite(data[off:off + (e - b)], base + b):
            m = needle.search(ops)
            if m:
                per_func.setdefault((b, e), []).append(
                    (addr - base, mnem, ops))

    lines: list[str] = []
    def p(s: str = "") -> None:
        lines.append(s)
    p("=== _vp_acc ===")
    p(f"functions_with_refs={len(per_func)}")
    for (b, e), hits in sorted(per_func.items()):
        p("")
        p(f"func 0x{b:X}..0x{e:X} size=0x{e-b:X} refs={len(hits)}"
          f"{'  [SMALL]' if (e - b) <= SMALL else ''}")
        for rva, mnem, ops in hits:
            p(f"    {rva:08X}  {mnem:<10} {ops}")

    # Vtable resolution for every function that reads (not writes) P0 or M0.
    def rva_to_off(r: int) -> int | None:
        for s in pe.sections:
            lo, hi = s.VirtualAddress, s.VirtualAddress + s.SizeOfRawData
            if lo <= r < hi:
                return s.PointerToRawData + (r - lo)
        return None

    readers = []
    for (b, e), hits in per_func.items():
        if (e - b) > SMALL:
            continue
        txt = " ".join(ops for _, _, ops in hits)
        if "P0" in txt or "P1" in txt:
            readers.append((b, e))
    p("")
    p(f"small_readers={[(hex(b), hex(e)) for b, e in sorted(readers)]}")
    p("vtable hits:")
    for b, e in sorted(readers):
        tgt = struct.pack("<Q", base + b)
        for s in pe.sections:
            name = s.Name.rstrip(b"\x00").decode(errors="replace")
            if name not in (".rdata", ".data", "_RDATA"):
                continue
            lo = s.PointerToRawData
            hi = lo + s.SizeOfRawData
            j = lo
            while True:
                j = data.find(tgt, j, hi)
                if j < 0:
                    break
                k = j
                while k - 8 >= lo:
                    q = struct.unpack_from("<Q", data, k - 8)[0]
                    if base <= q < base + pe.OPTIONAL_HEADER.SizeOfImage:
                        k -= 8
                    else:
                        break
                idx = (j - k) // 8
                run = 0
                while True:
                    q2 = struct.unpack_from("<Q", data, k + run * 8, ) [0]
                    if base <= q2 < base + pe.OPTIONAL_HEADER.SizeOfImage:
                        run += 1
                    else:
                        break
                p(f"  func 0x{b:X} in {name} table_run_len={run} slot=0x{idx*8:X} "
                  f"table_va=0x{base + (s.VirtualAddress + (k - lo)):X}")
                j += 1

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {OUT}: {len(lines)} lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
