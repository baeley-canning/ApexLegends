#!/usr/bin/env python3
"""Where does the ViewRender singleton come from, and can 0x9440B4 be its member?"""
from __future__ import annotations

import struct

import capstone
import pefile

EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
OUT = r"C:\Users\New User\OneDrive\Desktop\cheating\temp\_vp_origin_out.txt"
CAND = 0x9440B4
OFF = (0x11A390, 0x11A2D0, 0x11A310, 0x11A398)


def main() -> int:
    pe = pefile.PE(EXE, fast_load=True)
    data = open(EXE, "rb").read()
    base = pe.OPTIONAL_HEADER.ImageBase
    L: list[str] = []
    def p(s: str = "") -> None:
        L.append(s)

    p("=== sections ===")
    for s in pe.sections:
        p(f"  {s.Name.rstrip(chr(0).encode()).decode():<8} va=0x{s.VirtualAddress:X} "
          f"vsz=0x{s.Misc_VirtualSize:X} raw=0x{s.PointerToRawData:X} rawsz=0x{s.SizeOfRawData:X}")

    def rva2off(r: int) -> int | None:
        for s in pe.sections:
            if s.VirtualAddress <= r < s.VirtualAddress + s.SizeOfRawData:
                return s.PointerToRawData + (r - s.VirtualAddress)
        return None

    def sec_of(r: int) -> str:
        for s in pe.sections:
            if s.VirtualAddress <= r < s.VirtualAddress + s.Misc_VirtualSize:
                return s.Name.rstrip(b"\x00").decode()
        return "?"

    p("")
    p("=== candidate-object bases implied by the standing static 0x%X ===" % CAND)
    for o in OFF:
        v = CAND - o
        p(f"  cand-offset 0x{o:X} -> object rva 0x{v:X} ({sec_of(v)})")

    p("")
    p("=== bytes at 0x%X (raw file, initial value) ===" % CAND)
    for r in range(CAND - 0x20, CAND + 0x60, 0x10):
        off = rva2off(r)
        if off is None:
            p(f"  {r:X}: <bss>")
            continue
        chunk = data[off:off + 0x10]
        fl = struct.unpack("<4f", chunk)
        p(f"  {r:X}: {chunk.hex(' ')}  | " + " ".join(f"{v:+.6g}" for v in fl))

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.skipdata = True

    def dump(start: int, n: int, title: str) -> None:
        p("")
        p(f"=== {title} 0x{start:X} ===")
        off = rva2off(start)
        if off is None:
            p("  <not raw-backed>")
            return
        for i in md.disasm(data[off:off + n], base + start):
            p(f"  {i.address - base:08X}  {i.mnemonic:<10} {i.op_str}")

    dump(0x20B8A00, 0x70, "GetViewRenderInstance caller")
    dump(0x22670F0, 0x140, "candidate getter body")
    dump(0x20BA9A0, 0x40, "tiny global reader 20BA9A0")
    dump(0x2266D90, 0x60, "tiny global reader 2266D90")

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")
    print(f"wrote {OUT}: {len(L)} lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
