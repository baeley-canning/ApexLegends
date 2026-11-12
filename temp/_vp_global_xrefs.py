#!/usr/bin/env python3
"""Correlate a candidate ViewRender global with matrix-offset accesses.

Read-only.  Writes UTF-8 to temp\\_vp_global_xrefs_out.txt.
"""
from __future__ import annotations

import re
import struct

import capstone
import pefile

EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
OUT = r"C:\Users\New User\OneDrive\Desktop\cheating\temp\\_vp_global_xrefs_out.txt"
CANDIDATE_GLOBALS = [0x5267B70]
MATRIX_OFFSETS = [0x11A2D0, 0x11A310, 0x11A390, 0x11A398, 0x11A3A0]
EXTRA_FUNCS = [0x22670F0]
RIP_RE = re.compile(r"\[rip\s*([+-])\s*0x([0-9a-fA-F]+)\]")
DISP_RE = re.compile(r"\+ 0x([0-9a-fA-F]+)")


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
    pdata = next(s for s in pe.sections if s.Name.startswith(b".pdata"))
    poff, psize = pdata.PointerToRawData, pdata.Misc_VirtualSize
    funcs = []
    for i in range(0, psize - 11, 12):
        begin, end, unwind = struct.unpack_from("<III", data, poff + i)
        if begin and end > begin and text_rva <= begin < text_rva + text_size:
            funcs.append((begin, min(end, text_rva + text_size), unwind))
    funcs.sort()

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = False
    md.skipdata = True
    global_refs: list[tuple[int, int, int]] = []
    matrix_refs: dict[int, list[tuple[int, int, int]]] = {o: [] for o in MATRIX_OFFSETS}
    calls: dict[int, list[int]] = {}
    all_funcs = {b: (b, e, u) for b, e, u in funcs}

    def code_of(begin, end):
        off = rva_to_off(pe, begin)
        return data[off:off + (end - begin)]

    for begin, end, unwind in funcs:
        for addr, size, mnemonic, op_str in md.disasm_lite(code_of(begin, end), image_base + begin):
            rva = addr - image_base
            if "rip" in op_str:
                m = RIP_RE.search(op_str)
                if m:
                    disp = int(m.group(2), 16)
                    if m.group(1) == "-":
                        disp = -disp
                    target = rva + size + disp
                    if target in CANDIDATE_GLOBALS:
                        global_refs.append((rva, begin, end))
            if mnemonic.startswith("call"):
                m = re.search(r"0x([0-9a-fA-F]+)$", op_str)
                if m:
                    callee = int(m.group(1), 16) - image_base
                    calls.setdefault(callee, []).append(rva)
            # matrix offset is usually an immediate displacement; match exact
            # qword values only in operand text and avoid RIP targets.
            if "rip" not in op_str:
                for off in MATRIX_OFFSETS:
                    if f"0x{off:x}" in op_str.lower():
                        matrix_refs[off].append((rva, begin, end))

    lines: list[str] = []
    def p(s: str = "") -> None:
        lines.append(s)
    p("=== _vp_global_xrefs ===")
    p(f"functions={len(funcs)} candidate_globals={[hex(x) for x in CANDIDATE_GLOBALS]}")
    p(f"global_refs={len(global_refs)}")
    for rva, begin, end in global_refs:
        p(f"  global_ref rva=0x{rva:X} func=0x{begin:X}..0x{end:X}")
    p("matrix refs:")
    for off in MATRIX_OFFSETS:
        refs = matrix_refs[off]
        fns = sorted({(b, e) for _, b, e in refs})
        p(f"  +0x{off:X}: refs={len(refs)} funcs={len(fns)}")
        for b, e in fns:
            p(f"    func 0x{b:X}..0x{e:X}")
    for callee in EXTRA_FUNCS:
        p("")
        p(f"extra function 0x{callee:X} callers={len(calls.get(callee, []))}")
        for site in calls.get(callee, [])[:50]:
            p(f"  called_from=0x{site:X}")
        if callee in all_funcs:
            b, e, u = all_funcs[callee]
            mdd = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
            mdd.detail = True
            mdd.skipdata = True
            p(f"--- dump 0x{b:X}..0x{e:X} ---")
            for insn in mdd.disasm(code_of(b, e), image_base + b):
                p(f"  {insn.address - image_base:08X}  {insn.mnemonic:<10} {insn.op_str}")

    # Dump each function that references the candidate global.
    seen = set()
    mdd = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    mdd.detail = True
    mdd.skipdata = True
    for rva, begin, end in global_refs:
        if (begin, end) in seen:
            continue
        seen.add((begin, end))
        p("")
        p(f"--- global function 0x{begin:X}..0x{end:X} ---")
        for insn in mdd.disasm(code_of(begin, end), image_base + begin):
            mark = " <== GLOBAL" if insn.address - image_base == rva else ""
            p(f"  {insn.address - image_base:08X}  {insn.mnemonic:<10} {insn.op_str}{mark}")

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {OUT}: {len(lines)} lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
