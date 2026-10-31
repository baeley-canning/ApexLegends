"""r5apex_dx12.exe offset prober (static image + optional live validation).

Three independent resolvers, in order of trustworthiness:

  1. RTTI "globals" pass (apexdream offsets/src/analysis/globals.rs): walk every
     aligned qword in .rdata/.data, treat it as a vtable pointer, and recover the
     class name from the CompleteObjectLocator at vtable-8.  This finds the
     *instance slots* of CViewRender / CGameEntitySystem / CClientState without
     any byte signature, so a patch cannot silently invalidate it.
  2. Signature pass: apexdream misc.rs/globals.rs patterns, plus looser fallbacks
     for cl_entitylist (num_ent_entries -> cl_entitylist pairing).
  3. Datamap pass: MSVC datamap_t/typedescription_t dump, so member offsets
     (health / team / origin / camera) come from *this* build.

Usage:
    python temp/offsets_probe.py                  # static only
    python temp/offsets_probe.py --live [pid]    # + ReadProcessMemory checks
"""
import ctypes
import ctypes.wintypes as wt
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATH = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
data = open(PATH, "rb").read()


pe = struct.unpack_from("<I", data, 0x3C)[0]
nsec = struct.unpack_from("<H", data, pe + 6)[0]
opt_size = struct.unpack_from("<H", data, pe + 20)[0]
opt = pe + 24
IMAGE_BASE = struct.unpack_from("<Q", data, opt + 24)[0]
SIZE_OF_IMAGE = struct.unpack_from("<I", data, opt + 56)[0]
SIZE_OF_HEADERS = struct.unpack_from("<I", data, opt + 60)[0]

secs = []
for i in range(nsec):
    o = opt + opt_size + i * 40
    name = data[o:o + 8].rstrip(b"\x00").decode("latin1")
    vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, o + 8)
    secs.append((name, va, vsize, rawptr, rawsize))
SEC = {s[0]: s for s in secs}


def rva2off(rva):
    for name, va, vsize, rawptr, rawsize in secs:
        if rawptr and va <= rva < va + rawsize:
            return rawptr + (rva - va)
    return None


def off2rva(off):
    for name, va, vsize, rawptr, rawsize in secs:
        if rawptr and rawptr <= off < rawptr + rawsize:
            return va + (off - rawptr)
    return None


def rd(rva, n):
    o = rva2off(rva)
    return None if o is None else data[o:o + n]


def u32(rva):
    b = rd(rva, 4)
    return None if not b or len(b) < 4 else struct.unpack("<I", b)[0]


def u64(rva):
    b = rd(rva, 8)
    return None if not b or len(b) < 8 else struct.unpack("<Q", b)[0]


def cstr(rva, maxlen=160):
    o = rva2off(rva)
    if o is None:
        return None
    end = data.find(b"\x00", o, o + maxlen)
    if end < 0:
        return None
    try:
        s = data[o:end].decode("ascii")
    except UnicodeDecodeError:
        return None
    return s if all(32 <= ord(c) < 127 for c in s) else None


def va2rva(va):
    r = va - IMAGE_BASE
    return r if 0 <= r < SIZE_OF_IMAGE else None




# ---------------------------------------------------------------------------
# pelite-compatible pattern engine (the subset apexdream signatures use)
#   "4863C1"  fixed bytes        "?" one wildcard        "%" one wildcard
#   "[n]"     skip n bytes        "u4"/"u2"/"u1" capture LE immediate
#   "$"       capture rel32 -> target RVA                     "$*" same, no cap
#   'str'     trailing literal used only for sanity
# ---------------------------------------------------------------------------
HEX = set("0123456789abcdefABCDEF")
TEXT = SEC[".text"]


def compile_pattern(pat):
    toks, i = [], 0
    while i < len(pat):
        c = pat[i]
        if c.isspace():
            i += 1
        elif c in "?%":
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
            toks.append(("rel32", None))
        elif c == "@":
            j = i + 1
            while j < len(pat) and pat[j].isdigit():
                j += 1
            toks.append(("align", int(pat[i + 1:j]))); i = j
        elif all(ch in HEX for ch in pat[i:i + 2]) and len(pat[i:i + 2]) == 2:
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


def find_all(pattern, limit=8, section=".text"):
    """[(file_off, [code_rva, saves...])]; rel32 -> target RVA, u* -> int."""
    toks = compile_pattern(pattern)
    rx = _regex_for(toks)
    first = bytes([toks[0][1]]) if toks and toks[0][0] == "byte" else None
    sec = SEC[section]
    lo, hi = sec[3], sec[3] + sec[4]
    results, pos = [], lo
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


def report(label, pattern, limit=4, section=".text"):
    hits = find_all(pattern, limit, section)
    if not hits:
        print("  %-22s MISS   %s" % (label, pattern))
        return []
    for off, saves in hits:
        detail = " ".join(
            ("rva=%#010x" % s) if (s is not None and s > 0x10000) else ("imm=%#x" % s)
            for s in saves[1:])
        print("  %-22s code=%#010x %s" % (label, off2rva(off), detail))
    return [s for _, s in hits]


# ---------------------------------------------------------------------------
# 1. RTTI globals pass
#    For each aligned qword in .rdata/.data, assume it is a vtable pointer and
#    walk CompleteObjectLocator -> TypeDescriptor to recover the class name.
#    This yields (a) the vtable VA of every polymorphic class and (b) the RVA of
#    every statically initialised instance ("global") of those classes, so a
#    patch cannot silently invalidate the lookup the way a byte signature can.
# ---------------------------------------------------------------------------
def rva2va(rva):
    return IMAGE_BASE + rva


def va2rva(va):
    r = va - IMAGE_BASE
    return r if 0 <= r < SIZE_OF_IMAGE else None


INTERESTING = (
    "ViewRender", "GameEntitySystem", "ClientState", "GlobalVars", "Camera",
    "EngineClient", "GameMovement", "ModelInfo", "MaterialSystem", "GameRules",
    "Input", "EntityList", "Prediction", "EngineTrace", "StudioRender",
    "ModelRender", "TraceManager", "GameEventManager", "NetworkStringTable",
)


def class_of_vtable(vtable_va):
    """vtable VA -> class name, or None when it is not an MSVC vtable."""
    if va2rva(vtable_va) is None:
        return None
    col_va = u64(va2rva(vtable_va - 8))
    if not col_va:
        return None
    col_rva = va2rva(col_va)
    if col_rva is None:
        return None
    raw = rd(col_rva, 0x18)
    if raw is None or len(raw) < 0x18:
        return None
    signature, _off, _cd, td_rva, _cls, _self = struct.unpack("<IIIIII", raw)
    if signature not in (0, 1) or not (0 < td_rva < SIZE_OF_IMAGE):
        return None
    name = cstr(td_rva + 16, 200)
    if not name or not name.startswith(".?AV") or not name.endswith("@@"):
        return None
    return name[4:-2]


def scan_globals():
    """(instances, vtables): {class: [(slot_rva, vtable_rva)]}, {rva: class}"""
    instances, vtables, cache = {}, {}, {}
    for sname in (".rdata", ".data", ".pdata"):
        sec = SEC.get(sname)
        if not sec:
            continue
        name, va, vsize, rawptr, rawsize = sec
        for off in range(rawptr, rawptr + rawsize - 8, 8):
            val = struct.unpack_from("<Q", data, off)[0]
            if val < IMAGE_BASE or val >= IMAGE_BASE + SIZE_OF_IMAGE:
                continue
            if val not in cache:
                cache[val] = class_of_vtable(val)
            cname = cache[val]
            if not cname:
                continue
            slot_rva = va + (off - rawptr)
            instances.setdefault(cname, []).append((slot_rva, val - IMAGE_BASE))
            vtables.setdefault(val - IMAGE_BASE, cname)
    return instances, vtables




# ---------------------------------------------------------------------------
# 2. Datamap pass  (MSVC datamap_t / typedescription_t, see datamaps.rs)
#     typedescription_t (0x80): +0x00 type | +0x08 name | +0x10 offset
#                               +0x48 embedded datamap | +0x50 size
#     datamap_t (0x30):        +0x00 desc | +0x08 count | +0x10 name
#                               +0x28 baseMap
#     Every entity class exposes `lea rax,[rip+dm]; ret` so those thunks seed
#     the walk; embedded sub-datamaps are followed recursively.
# ---------------------------------------------------------------------------
TYPES = ("Void Float String Vector Quaternion Int Bool Short Char Color32 "
         "Embedded Custom ClassPtr EHANDLE edict PositionVector Time Tick "
         "ModelName SoundName").split()
NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_<>: ]*$")


def read_datamap(rva):
    if rva2off(rva) is None:
        return None
    desc, count, cls_va = u64(rva), u32(rva + 8), u64(rva + 0x10)
    base_va = u64(rva + 0x28)
    if not desc or not count or count > 4000:
        return None
    cls = va2rva(cls_va)
    name = cstr(cls) if cls is not None else None
    if not name or not NAME_RE.match(name):
        return None
    base = None
    if base_va:
        br = va2rva(base_va)
        if br is not None:
            bn = u64(br + 0x10)
            if bn:
                base = cstr(va2rva(bn) or 0)
    desc_rva = va2rva(desc)
    raw = rd(desc_rva, count * 0x80) if desc_rva is not None else None
    if not raw or len(raw) < count * 0x80:
        return None
    fields, bad = [], 0
    for i in range(count):
        p = i * 0x80
        ftype = struct.unpack_from("<i", raw, p)[0]
        fname_va = struct.unpack_from("<Q", raw, p + 0x08)[0]
        off = struct.unpack_from("<I", raw, p + 0x10)[0]
        td = struct.unpack_from("<Q", raw, p + 0x48)[0]
        fr = va2rva(fname_va)
        fname = cstr(fr, 96) if fr is not None else None
        if (ftype < 0 or ftype > 0x3F or not fname
                or not NAME_RE.match(fname) or off > 0x8000):
            bad += 1
            continue
        ty = TYPES[ftype] if ftype < len(TYPES) else str(ftype)
        fields.append((fname, off, ty, va2rva(td) if td else None))
    if bad > max(2, count // 8):
        return None
    return name, base, fields


def dump_datamaps():
    """{class_name: (datamap_rva, base_class, [(field, off, type, td_rva)])}"""
    seeds = []
    for _, saves in find_all("488D05 $ C3 CC CC CC CC CC CC CC CC", limit=20000):
        if saves[1] not in seeds:
            seeds.append(saves[1])
    maps, i = {}, 0
    while i < len(seeds):
        rva = seeds[i]
        i += 1
        dm = read_datamap(rva)
        if dm is None:
            continue
        name, base, fields = dm
        if name in maps:
            continue
        maps[name] = (rva, base, fields)
        for f in fields:
            if f[3] is not None and f[3] not in seeds:
                seeds.append(f[3])
    return maps


# ---------------------------------------------------------------------------
# 3. Signature pass (apexdream globals.rs / misc.rs, re-run on this build)
# ---------------------------------------------------------------------------
SIGS = [
    ("local_entity_handle", "8B05 $ 440FB705 ???? 83F8FF 74", 4),
    ("local_player", "488B05 $ 488D0D ???? 4488 ????? 4C89", 4),
    ("global_vars", "488B01 488D15 $ FF5010 85C0 75", 4),
    ("view_render", "488B0D $ 488B01 FF5020 488B0D", 8),
    ("view_render_alt", "0F85 ????? 488B0D $ 488B01 FF5020", 6),
    ("name_list", "48634338 488D0D $ 488D0440 488B44C1E8", 4),
    ("studio_hdr", "488B9F u4 4885DB 75? 488D0D $", 4),
    ("camera", "488BF9 0F2E89 u4 7A", 6),
    ("last_visible", "4C8BCE 498B3E F3410F1081 u4 663B774E", 6),
    ("highlight_settings", "488B15 $ 4803D1 4C8D0440", 6),
    ("network_var_table", "486BCA38 488D15 $ 837C110C07", 4),
    # cl_entitylist loose forms (the exact 2023 pattern is gone)
    ("entitylist_a", "81F9 u4 7C% 85C9 79%", 12),
    ("entitylist_b", "85C9 79% 4863C1 488D0D $", 12),
    ("entitylist_c", "4863C1 488D0D $", 40),
    ("entitylist_d", "4863C1 488D15 $", 40),
]


# ---------------------------------------------------------------------------
# 4. Live validation (optional): ReadProcessMemory against a running game
# ---------------------------------------------------------------------------
class MODULEENTRY32W(ctypes.Structure):
    _fields_ = [
        ("dwSize", wt.DWORD), ("th32ModuleID", wt.DWORD),
        ("th32ProcessID", wt.DWORD), ("GlblcntUsage", wt.DWORD),
        ("ProccntUsage", wt.DWORD),
        ("modBaseAddr", ctypes.POINTER(ctypes.c_ubyte)),
        ("modBaseSize", wt.DWORD), ("hModule", wt.HMODULE),
        ("szModule", ctypes.c_wchar * 256), ("szExePath", ctypes.c_wchar * 260),
    ]


class Live(object):
    PROCESS_VM_READ = 0x0010
    PROCESS_QUERY_INFORMATION = 0x0400

    def __init__(self, pid=None, exe="r5apex_dx12.exe"):
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        self.k32 = k32
        self.pid = pid or self._find_pid(exe)
        self.h = k32.OpenProcess(self.PROCESS_VM_READ |
                                 self.PROCESS_QUERY_INFORMATION, False, self.pid)
        if not self.h:
            raise OSError("OpenProcess(%d) failed: %d" % (self.pid, ctypes.get_last_error()))
        self.base, self.size = self._module(exe)

    def _find_pid(self, exe):
        snap = self.k32.CreateToolhelp32Snapshot(0x2 | 0x8, 0)  # SNAPSHOT_PROCESS
        pe = ctypes.create_string_buffer(0x300)
        struct.pack_into("<I", pe, 0, 0x300)
        try:
            if not self.k32.Process32First(snap, pe):
                raise OSError("Process32First failed")
            while True:
                name = pe.raw[0x2C:0x2C + 260].decode("utf-16-le").split("\x00")[0]
                if name.lower() == exe.lower():
                    return struct.unpack_from("<I", pe.raw, 8)[0]
                if not self.k32.Process32Next(snap, pe):
                    break
        finally:
            self.k32.CloseHandle(snap)
        raise OSError("%s is not running" % exe)

    def _module(self, exe):
        snap = self.k32.CreateToolhelp32Snapshot(0x8 | 0x10, self.pid)  # MODULE
        me = MODULEENTRY32W()
        me.dwSize = ctypes.sizeof(me)
        try:
            if not self.k32.Module32FirstW(snap, ctypes.byref(me)):
                raise OSError("Module32First failed")
            while True:
                if me.szModule.lower() == exe.lower():
                    return (ctypes.cast(me.modBaseAddr, ctypes.c_void_p).value,
                            me.modBaseSize)
                if not self.k32.Module32NextW(snap, ctypes.byref(me)):
                    break
        finally:
            self.k32.CloseHandle(snap)
        raise OSError("module %s not found" % exe)

    def read(self, addr, n):
        buf = ctypes.create_string_buffer(n)
        got = ctypes.c_size_t()
        ok = self.k32.ReadProcessMemory(ctypes.c_void_p(self.h), ctypes.c_void_p(addr),
                                        buf, n, ctypes.byref(got))
        return buf.raw[:got.value] if ok and got.value == n else None

    def u64(self, addr):
        b = self.read(addr, 8)
        return None if b is None else struct.unpack("<Q", b)[0]

    def u32(self, addr):
        b = self.read(addr, 4)
        return None if b is None else struct.unpack("<I", b)[0]

    def i32(self, addr):
        b = self.read(addr, 4)
        return None if b is None else struct.unpack("<i", b)[0]

    def f32(self, addr, n=1):
        b = self.read(addr, 4 * n)
        return None if b is None else struct.unpack("<%df" % n, b)

    def ptr_ok(self, v):
        return v is not None and 0x10000 < v < 0x7FFFFFFFFFFF and self.u64(v) is not None



# ---------------------------------------------------------------------------
# 5. Driver
# ---------------------------------------------------------------------------
def fmt(s):
    return ("rva=%#010x" % s) if s > 0x10000 else ("imm=%#x" % s)


def main(argv):
    args = [a for a in argv[1:]]
    want_rtti = "--no-rtti" not in args
    want_maps = "--no-datamaps" not in args
    pid = None
    if "--live" in args:
        i = args.index("--live")
        if i + 1 < len(args) and args[i + 1].isdigit():
            pid = int(args[i + 1])

    out = []

    def p(line=""):
        out.append(line)

    p("# r5apex_dx12.exe static offset probe")
    p("file      %s" % PATH)
    p("imagebase %#x  size %#x  sections %d" % (IMAGE_BASE, SIZE_OF_IMAGE, len(SEC)))
    for k in sorted(SEC, key=lambda s: SEC[s][1]):
        n, va, vs, raw, rs = SEC[k]
        p("  %-9s va=%#010x vsize=%#010x raw=%#010x rawsize=%#010x" %
          (n, va, vs, raw, rs))

    p("")
    p("## signatures (.text, %d bytes)" % len(TEXT and data[TEXT[3]:TEXT[3] + TEXT[4]]))
    sig = {}
    for label, pat, lim in SIGS:
        hits = find_all(pat, lim)
        sig[label] = hits
        if not hits:
            p("  %-22s MISS" % label)
            continue
        for off, saves in hits[:6]:
            p("  %-22s code=%#010x %s" %
              (label, off2rva(off), " ".join(fmt(s) for s in saves[1:])))
        if len(hits) > 6:
            p("  %-22s (+%d more)" % ("", len(hits) - 6))

    if want_rtti:
        p("")
        p("## RTTI globals (.rdata/.data/.pdata aligned qwords)")
        inst, vt = scan_globals()
        p("  classes with vtables: %d   vtable slots seen: %d" %
          (len(inst), len(vt)))
        for name in sorted(inst):
            if any(k.lower() in name.lower() for k in INTERESTING):
                for slot, vtr in sorted(inst[name]):
                    p("  [Global] %-46s slot=%#010x vtable=%#010x" %
                      (name, slot, vtr))
        p("")
        p("  -- all classes whose name matches PLAYER/ENTITY/NPC --")
        for name in sorted(inst):
            if any(k in name.upper() for k in ("PLAYER", "C_BASEENTITY", "NPC", "AI_")):
                slots = sorted(inst[name])
                p("  %-46s n=%d  first_slot=%#010x vtable=%#010x" %
                  (name, len(slots), slots[0][0], slots[0][1]))

    if want_maps:
        p("")
        p("## datamaps")
        maps = dump_datamaps()
        p("  datamaps parsed: %d" % len(maps))
        keys = sorted(maps)
        with open(os.path.join(HERE, "datamaps.txt"), "w", encoding="utf-8") as fh:
            for k in keys:
                rva, base, fields = maps[k]
                fh.write("[%s] rva=%#x base=%s fields=%d\n" %
                         (k, rva, base or "-", len(fields)))
                for fname, off, ty, td in fields:
                    fh.write("    %-40s +%#06x  %s\n" % (fname, off, ty))
        interesting_fields = ("health", "team", "origin", "camera", "visible",
                              "highlight", "shield", "armor", "life", "bleed",
                              "signifier", "angles", "position")
        for k in keys:
            if not any(t in k.upper() for t in ("PLAYER", "C_BASEENTITY", "NPC")):
                continue
            rva, base, fields = maps[k]
            p("")
            p("  %s (base=%s, %d fields)" % (k, base or "-", len(fields)))
            for fname, off, ty, td in fields:
                if any(t in fname.lower() for t in interesting_fields):
                    p("    %-38s +%#06x %s" % (fname, off, ty))
    else:
        maps = {}

    path = os.path.join(HERE, "offsets_static.txt")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    print("\n".join(out))
    print("\n[written] %s" % path)
    return sig, maps


if __name__ == "__main__":
    main(sys.argv)

