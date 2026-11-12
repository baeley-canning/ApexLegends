#!/usr/bin/env python3
"""Disassemble the functions around known matrix-offset accesses.

Read-only.  Writes UTF-8 to temp\\_vp_funcs_out.txt.
"""
from __future__ import annotations

import struct

import capstone
import pefile

EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
OUT = r"C:\Users\New User\OneDrive\Desktop\cheating\temp\\_vp_funcs_out.txt"
TEXT_HIT_OFFSETS = [
    0x20DA6D1, 0x20DA9A8, 0x226BE51, 0x226BF74, 0x226DD6C,
    0x226DF7D, 0x2275528, 0x2275891, 0x2277906, 0x227792F,
    0x2278593, 0x22785AD, 0x226BFA4, 0x226BFC2,
]
STRING_OFFSETS = [0x30EE7F8, 0x30EF1A0, 0x30EF1D7]


def sec_for_off(pe: pefile.PE, off: int):
    for sec in pe.sections:
        lo = sec.PointerToRawData
        hi = lo + sec.SizeOfRawData
        if lo <= off < hi:
            return sec
    return None


def off_to_rva(pe: pefile.PE, off: int) -> int:
    sec = sec_for_off(pe, off)
    if sec is None:
        raise ValueError(hex(off))
    return sec.VirtualAddress + (off - sec.PointerToRawData)


def rva_to_off(pe: pefile.PE, rva: int) -> int:
    for sec in pe.sections:
        lo = sec.VirtualAddress
        hi = lo + max(sec.Misc_VirtualSize, sec.SizeOfRawData)
        if lo <= rva < hi:
            return sec.PointerToRawData + (rva - lo)
    raise ValueError(hex(rva))


def main() -> int:
    pe = pefile.PE(EXE, fast_load=True)
    data = open(EXE, "rb").read()
    image_base = pe.OPTIONAL_HEADER.ImageBase
    text = pe.sections[0]
    text_rva = text.VirtualAddress
    text_size = text.Misc_VirtualSize

    # RUNTIME_FUNCTION table gives exact function boundaries.
    pdata_sec = next(s for s in pe.sections if s.Name.startswith(b".pdata"))
    pdata_off = pdata_sec.PointerToRawData
    pdata_size = pdata_sec.Misc_VirtualSize
    ranges: list[tuple[int, int, int, int]] = []
    for i in range(0, pdata_size - 11, 12):
        begin, end, unwind = struct.unpack_from("<III", data, pdata_off + i)
        if begin and end > begin and begin < pe.OPTIONAL_HEADER.SizeOfImage:
            ranges.append((begin, end, unwind, pdata_off + i))
    ranges.sort()

    def func_of(rva: int):
        for begin, end, unwind, rec in ranges:
            if begin <= rva < end:
                return begin, end, unwind, rec
        return None

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True

    lines: list[str] = []
    def p(s: str = "") -> None:
        lines.append(s)

    p("=== _vp_funcs ===")
    p(f"functions={len(ranges)} text_rva=0x{text_rva:X} text_size=0x{text_size:X}")

    # Locate RIP-relative refs to assertion/profiling strings by scanning all
    # text instructions once.  Record exact code sites.
    string_rvas = {rva: off for off in STRING_OFFSETS for rva in [off_to_rva(pe, off)]}
    string_xrefs: list[tuple[int, int, int]] = []
    text_off = text.PointerToRawData
    text_bytes = data[text_off:text_off + text_size]
    total_insns = 0
    for insn in md.disasm(text_bytes, image_base + text_rva):
        total_insns += 1
        for op in insn.operands:
            if op.type != capstone.x86.X86_OP_MEM:
                continue
            if op.mem.base != capstone.x86.X86_REG_RIP:
                continue
            target_va = insn.address + insn.size + op.mem.disp
            target_rva = target_va - image_base
            if target_rva in string_rvas:
                string_xrefs.append((insn.address - image_base, target_rva, insn.address))
    p(f"disassembled={total_insns} string_xrefs={len(string_xrefs)}")
    for rva, target, va in string_xrefs:
        fn = func_of(rva)
        p(f"  string_xref rva=0x{rva:X} va=0x{va:X} target=0x{target:X} "
          f"func={('0x%X..0x%X' % (fn[0], fn[1])) if fn else '?'}")

    # Function dumps around each matrix constant hit.
    seen: set[tuple[int, int]] = set()
    for off in TEXT_HIT_OFFSETS:
        rva = off_to_rva(pe, off)
        fn = func_of(rva)
        p("")
        p(f"--- hit off=0x{off:X} rva=0x{rva:X} ---")
        if fn is None:
            p("  no pdata function; dumping 0x120 bytes")
            start, end = max(text_rva, rva - 0x80), min(text_rva + text_size, rva + 0xA0)
        else:
            start, end = fn[0], fn[1]
            p(f"  function rva=0x{start:X}..0x{end:X} unwind=0x{fn[2]:X} "
              f"bytes=0x{end-start:X} rec_off=0x{fn[3]:X}")
            if (start, end) in seen:
                p("  (already dumped)")
                continue
            seen.add((start, end))
        start_off = rva_to_off(pe, start)
        code = data[start_off:start_off + (end - start)]
        for insn in md.disasm(code, image_base + start):
            mark = " <== HIT" if insn.address - image_base <= rva < insn.address - image_base + insn.size else ""
            p(f"  {insn.address - image_base:08X}  {insn.mnemonic:<10} {insn.op_str}{mark}")

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {OUT}: {len(lines)} lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
