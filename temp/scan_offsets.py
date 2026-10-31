"""Static offset resolver for r5apex_dx12.exe.

Runs the *real* apexdream (CasualX) byte signatures against the on-disk image
and resolves every global RVA the cheat needs, plus a datamap dump so member
offsets (health / team / origin) come from this build instead of 2023 notes.

Usage:
    python temp/scan_offsets.py                # static scan only
    python temp/scan_offsets.py --live         # + validate against live pid
    python temp/scan_offsets.py --live 11996   # explicit pid
"""
import re
import struct
import sys

PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
data = open(PATH, "rb").read()

# ---------------------------------------------------------------------------
# PE parsing
# ---------------------------------------------------------------------------
pe = struct.unpack_from("<I", data, 0x3C)[0]
nsec = struct.unpack_from("<H", data, pe + 6)[0]
opt_size = struct.unpack_from("<H", data, pe + 20)[0]
opt = pe + 24
IMAGE_BASE = struct.unpack_from("<Q", data, opt + 24)[0]
SIZE_OF_IMAGE = struct.unpack_from("<I", data, opt + 56)[0]

secs = []  # (name, va, vsize, rawptr, rawsize, chars)
sec_off = opt + opt_size
for i in range(nsec):
    o = sec_off + i * 40
    name = data[o:o + 8].rstrip(b"\x00").decode("latin1")
    vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, o + 8)
    chars = struct.unpack_from("<I", data, o + 36)[0]
    secs.append((name, va, vsize, rawptr, rawsize, chars))


def rva2off(rva):
    for name, va, vsize, rawptr, rawsize, chars in secs:
        if va <= rva < va + max(vsize, rawsize) and rawptr:
            return rawptr + (rva - va)
    return None


def off2rva(off):
    for name, va, vsize, rawptr, rawsize, chars in secs:
        if rawptr and rawptr <= off < rawptr + rawsize:
            return va + (off - rawptr)
    return None


def rd(rva, n):
    o = rva2off(rva)
    if o is None or o + n > len(data):
        return None
    return data[o:o + n]


def u32(rva):
    b = rd(rva, 4)
    return None if b is None else struct.unpack("<I", b)[0]


def u64(rva):
    b = rd(rva, 8)
    return None if b is None else struct.unpack("<Q", b)[0]


def cstr(rva, maxlen=200):
    o = rva2off(rva)
    if o is None:
        return None
    end = data.find(b"\x00", o, o + maxlen)
    if end < 0:
        return None
    try:
        return data[o:end].decode("ascii")
    except UnicodeDecodeError:
        return None


def rva_of_va(va):
    r = va - IMAGE_BASE
    if 0 <= r < SIZE_OF_IMAGE:
        return r
    return None


# ---------------------------------------------------------------------------
# pelite-compatible pattern engine (subset used by apexdream)
#   "4863C1"   fixed bytes
#   "?"        one wildcard byte
#   "[n]"      skip n bytes (still matched as wildcard)
#   "u4"/"u2"/"u1"  capture little-endian immediate
#   "${'}"     capture rel32 -> target RVA   (also accepts "$")
#   "$*'"      capture rel32 -> target RVA
#   "$"str""   capture rel32 -> target RVA of a C string (used only for sanity)
#   "@n"       alignment hint (ignored: fixed-width tokens already align)
# ---------------------------------------------------------------------------
HEX = set("0123456789abcdefABCDEF")


def compile_pattern(pat):
    toks, i = [], 0
    while i < len(pat):
        c = pat[i]
        if c.isspace():
            i += 1
        elif c == "?":
            toks.append(("skip", 1)); i += 1
        elif c == "[":
            j = pat.index("]", i)
            toks.append(("skip", int(pat[i + 1:j]))); i = j + 1
        elif pat.startswith("u4", i):
            toks.append(("cap", 4)); i += 2
        elif pat.startswith("u2", i):
            toks.append(("cap", 2)); i += 2
        elif pat.startswith("u1", i):
            toks.append(("cap", 1)); i += 2
        elif c == "$":
            i += 1
            while i < len(pat) and pat[i] in "*'":
                i += 1
            if i < len(pat) and pat[i] == '"':
                j = pat.index('"', i + 1)
                toks.append(("rel32", pat[i + 1:j])); i = j + 1
            else:
                toks.append(("rel32", None))
        elif c == "%":
            toks.append(("skip", 1)); i += 1
        elif c == "@":
            j = i + 1
            while j < len(pat) and pat[j].isdigit():
                j += 1
            toks.append(("align", int(pat[i + 1:j]))); i = j
        elif len(pat[i:i + 2]) == 2 and all(ch in HEX for ch in pat[i:i + 2]):
            toks.append(("byte", int(pat[i:i + 2], 16))); i += 2
        else:
            raise ValueError("bad pattern token at %d in %r" % (i, pat))
    return toks


def _regex_for(toks):
    out = b""
    for kind, val in toks:
        if kind == "byte":
            out += re.escape(bytes([val]))
        elif kind == "skip":
            out += b".{%d}" % val
        elif kind == "cap":
            out += b"(.{%d})" % val
        elif kind == "rel32":
            out += b"(.{4})"
    return re.compile(out, re.DOTALL)


def find_all(pattern, limit=8, text_only=True):
    """Return [(match_file_off, [saves])].  saves[0] is the match RVA; rel32
    tokens are resolved to target RVAs, u* tokens to integers."""
    toks = compile_pattern(pattern)
    rx = _regex_for(toks)
    first = bytes([toks[0][1]]) if toks and toks[0][0] == "byte" else None

    lo, hi = 0, len(data)
    if text_only:
        for name, va, vsize, rawptr, rawsize, chars in secs:
            if name == ".text":
                lo, hi = rawptr, rawptr + rawsize
                break

    results = []
    pos = lo
    while len(results) < limit:
        if first is not None:
            pos = data.find(first, pos, hi)
            if pos < 0:
                break
        m = rx.match(data, pos)
        if not m:
            pos += 1
            continue

        cur, gi, saves = pos, 0, [off2rva(pos)]
        for kind, val in toks:
            if kind == "byte":
                cur += 1
            elif kind in ("skip", "align"):
                cur += val
            elif kind in ("cap", "rel32"):
                raw = m.group(gi + 1)
                gi += 1

                if kind == "cap":
                    saves.append(int.from_bytes(raw, "little"))
                else:
                    disp = struct.unpack("<i", raw)[0]
                    saves.append(off2rva(cur) + 4 + disp)
                cur += len(raw)
        results.append((pos, saves))
        pos += 1
    return results


def report(label, pattern, limit=4):
    hits = find_all(pattern, limit)
    if not hits:
        print("%-22s NOT FOUND   %s" % (label, pattern))
        return []
    for off, saves in hits:
        rva = off2rva(off)
        detail = " ".join(
            ("rva=%#010x" % s) if (s is not None and s > 0x1000) else ("u=%#x" % s)
            for s in saves[1:])
        print("%-22s code=%#010x  %s" % (label, rva, detail))
    return [s for _, s in hits]


# apexdream signatures (offsets/src/analysis/globals.rs, misc.rs)
# ---------------------------------------------------------------------------
print("=== sections ===")
for name, va, vsize, rawptr, rawsize, chars in secs:
    print("  %-9s va=%#010x vsize=%#010x rawsize=%#010x" % (name, va, vsize, rawsize))

print("\n=== globals ===")
globals_found = {}

# cl_entitylist + num_ent_entries: bounds-checked accessor
#   cmp ecx, num_ent_entries ; jl ; test ecx,ecx ; jns ; movsxd rax,ecx ; lea rcx,[cl_entitylist]
hits = report("cl_entitylist", "81F9 u4 7C% 85C9 79% 4863C1 488D0D $", limit=6)

hits = report("local_entity_handle", "8B05 $ 440FB705 ???? 83F8FF 74", limit=4)

hits = report("local_player", "488B05 $ 488D0D ???? 4488 ????? 4C89", limit=4)

hits = report("global_vars", "488B01 488D15 $ FF5010 85C0 75", limit=4)

hits = report("view_render", "0F85 ????? 488B0D $ 488B01 FF5020 488B0D", limit=4)

hits = report("view_matrix", "4889 [5] 498BB5 u4 498B9D [4] E8", limit=4)

hits = report("name_list", "48634338 488D0D $ 488D0440 488B44C1E8", limit=4)

hits = report("studio_hdr", '488B9F u4 4885DB 75? 488D0D $"Entity has no model"', limit=4)

hits = report("camera", "488BF9 0F2E89 u4 7A", limit=4)

hits = report("last_visible", "4C8BCE 498B3E F3410F1081 u4 663B774E 0F83", limit=4)

hits = report("highlight_settings", "488B15 $ 4803D1 4C8D0440", limit=4)

hits = report("network_var_table", "486BCA38 488D15 $ 837C110C07", limit=4)
