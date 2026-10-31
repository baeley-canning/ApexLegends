"""dll_dis.py -- annotated linear disassembly of a PE (x64) for reverse work.

Usage:  python dll_dis.py <pe> [--from RVA --to RVA] [--grep TEXT]

* maps sections, resolves rip-relative operands to "section+off" / import names
* resolves `call qword ptr [rip+x]` to the imported API name via the IAT
* prints the import table, then the (optionally filtered) instruction listing
Everything is also written to <pe>.dis.txt
"""
import sys
import io
import os
import re

import capstone
import pefile


def load(path):
    pe = pefile.PE(path, fast_load=False)
    base = pe.OPTIONAL_HEADER.ImageBase
    secs = []
    for s in pe.sections:
        secs.append({
            "name": s.Name.rstrip(b"\0").decode("latin-1"),
            "va": base + s.VirtualAddress,
            "rva": s.VirtualAddress,
            "vsize": max(s.Misc_VirtualSize, s.SizeOfRawData),
            "data": s.get_data(),
        })
    imports = {}
    if hasattr(pe, "DIRECTORY_ENTRY_IMPORT"):
        for dll in pe.DIRECTORY_ENTRY_IMPORT:
            for imp in dll.imports:
                if imp.address:
                    imports[imp.address] = "%s!%s" % (
                        dll.dll.decode("latin-1"), (imp.name or b"#%d" % imp.ordinal).decode("latin-1"))
    exports = {}
    if hasattr(pe, "DIRECTORY_ENTRY_EXPORT"):
        for exp in pe.DIRECTORY_ENTRY_EXPORT.symbols:
            exports[base + exp.address] = exp.name
    return pe, base, secs, imports, exports


def sec_of(secs, va):
    for s in secs:
        if s["va"] <= va < s["va"] + s["vsize"]:
            return s, va - s["va"]
    return None, 0


def read_at(secs, va, n):
    s, off = sec_of(secs, va)
    if s is None or off + n > len(s["data"]):
        return None
    return s["data"][off:off + n]


def va_to_str(secs, base, va):
    raw = read_at(secs, va, 2)
    if not raw:
        return None
    if raw[1:2] == b"\0":
        s, off = sec_of(secs, va)
        end = s["data"].find(b"\0\0", off)
        if 0 < end - off < 300:
            try:
                return s["data"][off:end + 1].decode("utf-16-le", "replace")
            except Exception:
                return None
    raw = read_at(secs, va, 1)
    if raw and 32 <= raw[0] < 127:
        s, off = sec_of(secs, va)
        end = s["data"].find(b"\0", off)
        if 0 < end - off < 200:
            try:
                t = s["data"][off:end].decode("latin-1")
            except Exception:
                return None
            if all(32 <= c < 127 for c in s["data"][off:end]):
                return t
    return None


def main():
    path = sys.argv[1]
    lo = hi = None
    pat = None
    if "--from" in sys.argv:
        lo = int(sys.argv[sys.argv.index("--from") + 1], 16)
    if "--to" in sys.argv:
        hi = int(sys.argv[sys.argv.index("--to") + 1], 16)
    if "--grep" in sys.argv:
        pat = re.compile(sys.argv[sys.argv.index("--grep") + 1], re.I)

    pe, base, secs, imports, exports = load(path)
    out = []
    out.append("image base %#x" % base)
    for s in secs:
        out.append("  sec %-8s va=%#012x vsize=%#x raw=%#x" %
                   (s["name"], s["va"], s["vsize"], len(s["data"])))
    out.append("--- imports")
    for a in sorted(imports):
        out.append("  %#012x %s" % (a, imports[a]))
    out.append("--- exports")
    for a in sorted(exports):
        out.append("  %#012x %s" % (a, exports[a] or "?"))

    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = False
    text = [s for s in secs if s["name"] in (".text", "CODE")]
    for s in text:
        va = s["va"] if lo is None else max(s["va"], lo)
        end = s["va"] + min(s["vsize"], len(s["data"])) if hi is None else hi
        off = va - s["va"]
        code = s["data"][off:end - s["va"]]
        for ins in md.disasm(code, va):
            line = "  %012x  %-24s %-8s %s" % (
                ins.address, ins.bytes.hex(), ins.mnemonic, ins.op_str)
            notes = []
            m = re.search(r"\[rip \+ (0x[0-9a-f]+)\]", ins.op_str)
            if m:
                tgt = ins.address + ins.size + int(m.group(1), 16)
                if tgt in imports:
                    notes.append(imports[tgt])
                name = va_to_str(secs, base, tgt)
                sc, so = sec_of(secs, tgt)
                notes.append("%s+%#x" % (sc["name"] if sc else "?", so))
                if name:
                    notes.append(repr(name[:60]))
                line += "   ; " + " ".join(notes)
            m = re.match(r"(0x[0-9a-f]+)$", ins.op_str)
            if m and ins.mnemonic.startswith(("call", "jmp")):
                tgt = int(m.group(1), 16)
                nm = exports.get(tgt)
                if nm:
                    line += "   ; " + (nm.decode("latin-1") if isinstance(nm, bytes) else nm)
            if pat and not pat.search(line):
                continue
            out.append(line)

    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        os.path.basename(path) + ".dis.txt")
    io.open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("wrote %s (%d lines)" % (dst, len(out)))


main()
