#!/usr/bin/env python3
"""Find code xrefs to the CViewRender assertion strings.

Scans every .pdata function, so data/jump-table bytes do not stop the sweep.
Writes UTF-8 to temp\\_vp_string_xrefs_out.txt.
"""
from __future__ import annotations

import re
import struct

import capstone
import pefile

EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
OUT = r"C:\Users\New User\OneDrive\Desktop\cheating\temp\\_vp_string_xrefs_out.txt"
STRINGS = [
    (0x30EE7F8, "GetViewRenderInstance() must be implemented"),
    (0x30EF1A0, "CViewRender::SetUpView->OnRenderEnd"),
    (0x30EF1D7, "CViewRender::SetUpView"),
]
RIP_RE = re.compile(r"\[rip\s*([+-])\s*0x([0-9a-fA-F]+)\]")


def rva_to_off(pe: pefile.PE, rva: int) -> int:
    for sec in pe.sections:
        lo = sec.VirtualAddress
        hi = lo + max(sec.Misc_VirtualSize, sec.SizeOfRawData)
        if lo <= rva < hi:
            return sec.PointerToRawData + (rva - lo)
    raise ValueError(hex(rva))


def off_to_rva(pe: pefile.PE, off: int) -> int:
    for sec in pe.sections:
        lo = sec.PointerToRawData
        hi = lo + sec.SizeOfRawData
        if lo <= off < hi:
            return sec.VirtualAddress + (off - sec.PointerToRawData)
    raise ValueError(hex(off))


def main() -> int:
    pe = pefile.PE(EXE, fast_load=True)
    data = open(EXE, "rb").read()
    image_base = pe.OPTIONAL_HEADER.ImageBase
    text = pe.sections[0]
    text_rva = text.VirtualAddress
    text_size = text.Misc_VirtualSize
    pdata = next(s for s in pe.sections if s.Name.startswith(b".pdata"))
    poff = pdata.PointerToRawData
    psize = pdata.Misc_VirtualSize
    funcs = []
    for i in range(0, psize - 11, 12):
        begin, end, unwind = struct.unpack_from("<III", data, poff + i)
        if begin and end > begin and text_rva <= begin < text_rva + text_size:
            funcs.append((begin, min(end, text_rva + text_size), unwind))
    funcs.sort()
    targets = {off_to_rva(pe, off): label for off, label in STRINGS}

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = False
    md.skipdata = True
    hits: list[tuple[int, int, int, str]] = []
    total = 0
    for begin, end, unwind in funcs:
        code = data[rva_to_off(pe, begin):rva_to_off(pe, begin) + (end - begin)]
        for addr, size, mnemonic, op_str in md.disasm_lite(code, image_base + begin):
            total += 1
            if "rip" not in op_str:
                continue
            m = RIP_RE.search(op_str)
            if not m:
                continue
            disp = int(m.group(2), 16)
            if m.group(1) == "-":
                disp = -disp
            target = (addr + size + disp) - image_base
            if target in targets:
                hits.append((addr - image_base, begin, end, targets[target]))

    lines: list[str] = []
    def p(s: str = "") -> None:
        lines.append(s)
    p("=== _vp_string_xrefs ===")
    p(f"functions={len(funcs)} instructions={total} targets={[(hex(k), v) for k, v in targets.items()]}")
    p(f"hits={len(hits)}")
    for rva, begin, end, label in hits:
        p(f"  xref_rva=0x{rva:X} func=0x{begin:X}..0x{end:X} string={label!r}")

    # Detail dump for every function that contains a hit.
    mdd = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    mdd.detail = True
    mdd.skipdata = True
    seen = set()
    for rva, begin, end, label in hits:
        if (begin, end) in seen:
            continue
        seen.add((begin, end))
        p("")
        p(f"--- function 0x{begin:X}..0x{end:X} for {label!r} ---")
        code = data[rva_to_off(pe, begin):rva_to_off(pe, begin) + (end - begin)]
        for insn in mdd.disasm(code, image_base + begin):
            mark = " <== STRING_XREF" if insn.address - image_base == rva else ""
            p(f"  {insn.address - image_base:08X}  {insn.mnemonic:<10} {insn.op_str}{mark}")

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {OUT}: {len(lines)} lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
