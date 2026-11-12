#!/usr/bin/env python3
"""Read-only inventory for offline view-matrix work.

No process access, no driver, no game launch.  Writes only to stdout; the
caller redirects stdout to temp\\_vp_inventory_out.txt.
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
import struct
import sys

CANDIDATES = [
    r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe",
    r"C:\Program Files\EA Games\Apex\r5apex.exe",
    r"C:\Program Files (x86)\Steam\steamapps\common\Apex Legends\r5apex_dx12.exe",
    r"C:\Program Files (x86)\Steam\steamapps\common\Apex Legends\r5apex.exe",
]
MODULES = ["capstone", "pefile", "lief", "numpy"]


def sha256(path: str, limit: int | None = None) -> str:
    h = hashlib.sha256()
    left = limit
    with open(path, "rb") as f:
        while True:
            n = 1 << 20 if left is None else min(1 << 20, left)
            if n <= 0:
                break
            chunk = f.read(n)
            if not chunk:
                break
            h.update(chunk)
            if left is not None:
                left -= len(chunk)
    return h.hexdigest().upper()


def pe_info(path: str) -> dict:
    out: dict = {}
    with open(path, "rb") as f:
        f.seek(0)
        dos = f.read(0x40)
        out["mz"] = dos[:2].decode("ascii", "replace")
        e_lfanew = struct.unpack_from("<I", dos, 0x3C)[0]
        out["e_lfanew"] = hex(e_lfanew)
        f.seek(e_lfanew)
        nt = f.read(0x108)
        out["pe"] = nt[:4].decode("ascii", "replace")
        machine, nsec, stamp, _, _, opt_size, chars = struct.unpack_from(
            "<HHIIIHH", nt, 4
        )
        magic = struct.unpack_from("<H", nt, 24)[0]
        out.update(
            machine=hex(machine),
            sections=nsec,
            timedatestamp=hex(stamp),
            optional_size=hex(opt_size),
            characteristics=hex(chars),
            magic=hex(magic),
        )
        if magic == 0x20B:
            image_base = struct.unpack_from("<Q", nt, 24 + 24)[0]
            size_image = struct.unpack_from("<I", nt, 24 + 56)[0]
            checksum = struct.unpack_from("<I", nt, 24 + 64)[0]
            entry = struct.unpack_from("<I", nt, 24 + 16)[0]
            out.update(
                image_base=hex(image_base),
                size_of_image=hex(size_image),
                checksum=hex(checksum),
                entry_rva=hex(entry),
            )
        sections = []
        sec_off = 24 + opt_size
        f.seek(e_lfanew + 4 + 20 + opt_size)
        raw = f.read(40 * nsec)
        for i in range(nsec):
            ent = raw[i * 40:(i + 1) * 40]
            name = ent[:8].split(b"\0", 1)[0].decode("ascii", "replace")
            vsize, vaddr, rsize, roff = struct.unpack_from("<IIII", ent, 8)
            sflags = struct.unpack_from("<I", ent, 36)[0]
            sections.append(
                dict(
                    name=name,
                    va=hex(vaddr),
                    vsize=hex(vsize),
                    raw=hex(roff),
                    rawsize=hex(rsize),
                    flags=hex(sflags),
                )
            )
        out["sections"] = sections
    return out


def main() -> int:
    print("=== _vp_inventory (read-only) ===")
    print("python:", sys.version.replace("\n", " "))
    print("executable:", sys.executable)
    for mod in MODULES:
        spec = importlib.util.find_spec(mod)
        print(f"module {mod}: {bool(spec)}" + (f" ({spec.origin})" if spec else ""))
    print("PATH candidates:")
    for path in CANDIDATES:
        print(f"  exists={os.path.isfile(path)!s:5} {path}")
        if not os.path.isfile(path):
            continue
        st = os.stat(path)
        print(f"    size={st.st_size} mtime={st.st_mtime_ns} sha256={sha256(path)}")
        try:
            info = pe_info(path)
            print("    pe:", info)
        except Exception as exc:
            print(f"    pe_error: {type(exc).__name__}: {exc}")
    print("RESULT: INVENTORY_WRITTEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
