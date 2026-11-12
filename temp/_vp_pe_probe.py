#!/usr/bin/env python3
"""Read-only PE/RTTI/constant probe for the offline view-matrix solver.

Writes UTF-8 to temp\\_vp_pe_probe_out.txt.  No process access.
"""
from __future__ import annotations

import os
import re
import struct
import sys

import pefile

EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
OUT = r"C:\Users\New User\OneDrive\Desktop\cheating\temp\_vp_pe_probe_out.txt"
MAX_HITS = 80


def rva_to_off(pe: pefile.PE, rva: int) -> int | None:
    for sec in pe.sections:
        lo = sec.VirtualAddress
        hi = lo + max(sec.Misc_VirtualSize, sec.SizeOfRawData)
        if lo <= rva < hi:
            return sec.PointerToRawData + (rva - lo)
    return None


def main() -> int:
    lines: list[str] = []
    def p(s: str = "") -> None:
        lines.append(s)

    pe = pefile.PE(EXE, fast_load=True)
    p("=== _vp_pe_probe ===")
    p(f"file={EXE}")
    p(f"stamp=0x{pe.FILE_HEADER.TimeDateStamp:08X} checksum=0x{pe.OPTIONAL_HEADER.CheckSum:08X}")
    p(f"image_base=0x{pe.OPTIONAL_HEADER.ImageBase:X} size=0x{pe.OPTIONAL_HEADER.SizeOfImage:X}")
    p(f"sections={pe.FILE_HEADER.NumberOfSections}")
    for i, s in enumerate(pe.sections):
        p(f"  [{i}] {s.Name.rstrip(chr(0).encode()).decode(errors='replace')} "
          f"va=0x{s.VirtualAddress:X} vsz=0x{s.Misc_VirtualSize:X} "
          f"raw=0x{s.PointerToRawData:X} rawsz=0x{s.SizeOfRawData:X}")
    # Directories
    for name, idx in (("debug", pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_DEBUG"]),
                      ("reloc", pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_BASERELOC"]),
                      ("exception", pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_EXCEPTION"])):
        d = pe.OPTIONAL_HEADER.DATA_DIRECTORY[idx]
        p(f"dir {name}: rva=0x{d.VirtualAddress:X} size=0x{d.Size:X}")
    pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_DEBUG"]])
    for d in getattr(pe, "DIRECTORY_ENTRY_DEBUG", []):
        p(f"debug: type={d.struct.Type} rva=0x{d.struct.AddressOfRawData:X} "
          f"size=0x{d.struct.SizeOfData:X}")
        if d.struct.Type == 2 and d.entry:
            p(f"  pdb={getattr(d.entry, 'PdbFileName', b'?')!r} "
              f"guid_age={d.entry.PdbFileName!r}")

    data = open(EXE, "rb").read()
    p(f"read {len(data)} bytes")

    # ASCII and UTF-16LE RTTI-ish names.
    needles = [
        "CViewRender", "ViewRender", "C_ViewRender", "GetViewRender",
        "CClientState", "ClientState", "CView",
    ]
    for needle in needles:
        for enc, label in (("ascii", "A"), ("utf-16le", "W")):
            b = needle.encode(enc)
            hits = [m.start() for m in re.finditer(re.escape(b), data)]
            p(f"string {needle!r} [{label}]: {len(hits)}")
            for off in hits[:MAX_HITS]:
                before = data[max(0, off - 12):off]
                after = data[off + len(b):off + len(b) + 24]
                p(f"  off=0x{off:X} before={before.hex()} after={after.hex()}")

    # Raw occurrences of old matrix displacements.  These show both accessor
    # immediates and unrelated constants; context is what matters.
    text = pe.sections[0]
    text_off = text.PointerToRawData
    text_end = text_off + text.SizeOfRawData
    for value in (0x11A350, 0x11A390, 0x11A3B0, 0x11A330):
        pat = struct.pack("<I", value)
        hits = []
        start = text_off
        while True:
            j = data.find(pat, start, text_end)
            if j < 0:
                break
            hits.append(j)
            start = j + 1
        p(f"text constant 0x{value:X}: {len(hits)}")
        for off in hits[:MAX_HITS]:
            b = data[max(0, off - 24):off + 28]
            p(f"  off=0x{off:X} around={b.hex()}")

    p("RESULT_MARKER: done")
    p(f"RESULT: PE_PROBE_DONE candidates_need_review")
    textout = "\n".join(lines) + "\n"
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(textout)
    print(f"wrote {OUT}: {len(lines)} lines")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        import traceback
        with open(OUT, "w", encoding="utf-8") as f:
            f.write(traceback.format_exc())
        raise
