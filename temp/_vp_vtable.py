#!/usr/bin/env python3
"""Prove the ViewMatrix pointer-array offset by vtable slot index.

1. Find tiny accessors that touch +0x11A390 / +0x11A2D0 / +0x11A310.
2. Find their qword entries in .rdata / .data (vtables) and report slot index.
3. Cross-check the consumer at 0x20B7FD0 (call [rax+0x80] -> matrix ptr).
Writes UTF-8 to temp\\_vp_vtable_out.txt.
"""
from __future__ import annotations

import struct

import capstone
import pefile

EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
OUT = r"C:\Users\New User\OneDrive\Desktop\cheating\temp\\_vp_vtable_out.txt"
OFFSETS = (0x11A390, 0x11A2D0, 0x11A310, 0x11A398, 0x11A3A8)


def main() -> int:
    pe = pefile.PE(EXE, fast_load=True)
    data = open(EXE, "rb").read()
    base = pe.OPTIONAL_HEADER.ImageBase
    text = pe.sections[0]
    text_off, text_size, text_rva = text.PointerToRawData, text.Misc_VirtualSize, text.VirtualAddress
    blob = data[text_off:text_off + text_size]

    # Raw byte search for the 7-byte encodings.  `mov rax,[rcx+disp32]`
    # 48 8B 81 <disp32>, `lea rax,[rcx+disp32]` 48 8D 81 <disp32>.
    cands: list[tuple[int, str, int]] = []
    for off in OFFSETS:
        for prefix, kind in ((b"\x48\x8b\x81", "mov-rax"), (b"\x48\x8d\x81", "lea-rax"),
                             (b"\x48\x8b\x89", "mov-rcx"), (b"\x48\x8d\x89", "lea-rcx")):
            pat = prefix + struct.pack("<I", off)
            start = 0
            while True:
                j = blob.find(pat, start)
                if j < 0:
                    break
                cands.append((text_rva + j, kind, off))
                start = j + 1
    cands.sort()

    lines: list[str] = []
    def p(s: str = "") -> None:
        lines.append(s)
    p("=== _vp_vtable ===")
    p(f"accessor_candidates={len(cands)}")
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    for rva, kind, off in cands:
        code = data[text_off + (rva - text_rva): text_off + (rva - text_rva) + 24]
        insns = list(md.disasm(code, base + rva))[:4]
        txt = " ; ".join(f"{i.mnemonic} {i.op_str}" for i in insns)
        p(f"  0x{rva:X} [{kind} +0x{off:X}] {txt}")

    # Vtable sweep: qword entries in .rdata/.data equal to base+accessor_rva.
    def off_to_rva(o: int) -> int | None:
        for s in pe.sections:
            lo, hi = s.PointerToRawData, s.PointerToRawData + s.SizeOfRawData
            if lo <= o < hi:
                return s.VirtualAddress + (o - lo)
        return None

    def rva_to_off(r: int) -> int | None:
        for s in pe.sections:
            lo, hi = s.VirtualAddress, s.VirtualAddress + s.SizeOfRawData
            if lo <= r < hi:
                return s.PointerToRawData + (r - lo)
        return None

    p("")
    p("vtable_entries:")
    for rva, kind, off in cands:
        target = struct.pack("<Q", base + rva)
        for s in pe.sections:
            if not s.Name.rstrip(b"\x00").lower() in (b".rdata", b".data", b"_rdata"):
                continue
            lo, hi = s.PointerToRawData, s.PointerToRawData + s.SizeOfRawData
            start = lo
            while True:
                j = data.find(target, start, hi)
                if j < 0:
                    break
                start = j + 1
                # Walk back to the table head: contiguous run of qwords that
                # are all plausible RVAs of this image.
                k = j
                while k - 8 >= lo:
                    q = struct.unpack_from("<Q", data, k - 8)[0]
                    if base <= q < base + pe.OPTIONAL_HEADER.SizeOfImage:
                        k -= 8
                    else:
                        break
                idx = (j - k) // 8
                p(f"  0x{rva:X} -> table_rva=0x{(off_to_rva(k) or 0):X} slot=0x{idx*8:X} "
                  f"(entry_va=0x{base + (off_to_rva(j) or 0):X})")

    # Dump the table that holds the +0x11A390 accessor, with resolved names.
    p("")
    p("world_to_screen consumer sanity (0x20B7FD0):")
    code = data[text_off + 0x20B7FD0 - text_rva: text_off + 0x20B7FD0 - text_rva + 0x40]
    for insn in md.disasm(code, base + 0x20B7FD0):
        p(f"  {insn.address - base:08X}  {insn.mnemonic:<10} {insn.op_str}")

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {OUT}: {len(lines)} lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
