"""Live validation of static-signature candidates against the running game.

RTTI is absent from r5apex_dx12.exe (probe_pe.txt: /?AV count = 0), so a static
byte signature can only propose an RVA.  This script proves or disproves each
candidate with ReadProcessMemory:

  * cl_entitylist: the slot must hold a heap pointer whose first qword is a
    vtable inside the game image, and the elements must line up on either an
    8-byte or a 0x20-byte stride (Apex indexes entities by handle >> 5).
  * local_player: the slot must hold an entity that also appears in the entity
    list -- that cross-check is what makes the pair trustworthy.
  * view_render: the instance must contain a 16-float view matrix.

Output goes to temp/live1.txt (run_commands stdout is unreliable here).
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = "r5apex_dx12.exe"

# RVAs produced by temp/offsets_probe.py (probe_maps.txt) -- candidates only.
ENTITYLIST_C = [0x0335d680, 0x03013c80, 0x02fca848, 0x09b9a720]
LOCAL_PLAYER = [0x03e779d0]
VIEW_RENDER = [0x04068440, 0x05a64cb8, 0x03353680, 0x05a64c48, 0x05a64c78,
               0x05a64c40]
NAME_LIST = [0x09e2fc20]
GLOBAL_VARS = [0x03623ad0]
HANDLE_SIG = [0x03d218b0]
STUDIO_HDR = [0x0307f670]
HIGHLIGHT = [0x07b23040]

k32 = ctypes.WinDLL("kernel32", use_last_error=True)


class MODULEENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("th32ModuleID", wt.DWORD),
                ("th32ProcessID", wt.DWORD), ("GlblcntUsage", wt.DWORD),
                ("ProccntUsage", wt.DWORD), ("modBaseAddr", ctypes.POINTER(ctypes.c_byte)),
                ("modBaseSize", wt.DWORD), ("hModule", wt.HMODULE),
                ("szModule", wt.WCHAR * 256), ("szExePath", wt.WCHAR * 260)]


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD),
                ("th32ProcessID", wt.DWORD),
                ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
                ("th32ModuleID", wt.DWORD), ("cntThreads", wt.DWORD),
                ("th32ParentProcessID", wt.DWORD), ("pcPriClassBase", ctypes.c_long),
                ("dwFlags", wt.DWORD), ("szExeFile", wt.WCHAR * 260)]


class Live:
    def __init__(self):
        self.h = None
        self.pid = None
        self.base = 0
        self.size = 0
        snap = k32.CreateToolhelp32Snapshot(0x2, 0)  # TH32CS_SNAPPROCESS
        pe = PROCESSENTRY32W()
        pe.dwSize = ctypes.sizeof(pe)
        try:
            ok = k32.Process32FirstW(snap, ctypes.byref(pe))
            while ok:
                if pe.szExeFile.lower() == EXE.lower():
                    self.pid = pe.th32ProcessID
                    break
                ok = k32.Process32NextW(snap, ctypes.byref(pe))
        finally:
            k32.CloseHandle(snap)
        if not self.pid:
            raise OSError("%s is not running" % EXE)
        self.h = k32.OpenProcess(0x10 | 0x400, False, self.pid)  # VM_READ|QUERY_INFO
        if not self.h:
            raise OSError("OpenProcess(%d) failed err=%d" % (self.pid, ctypes.get_last_error()))
        self._module()

    def _module(self):
        snap = k32.CreateToolhelp32Snapshot(0x8 | 0x10, self.pid)  # MODULE|SNAP
        me = MODULEENTRY32W()
        me.dwSize = ctypes.sizeof(me)
        try:
            ok = k32.Module32FirstW(snap, ctypes.byref(me))
            while ok:
                if me.szModule.lower() == EXE.lower():
                    self.base = ctypes.cast(me.modBaseAddr, ctypes.c_void_p).value
                    self.size = me.modBaseSize
                    return
                ok = k32.Module32NextW(snap, ctypes.byref(me))
        finally:
            k32.CloseHandle(snap)
        raise OSError("module %s not found" % EXE)

    def read(self, addr, n):
        buf = ctypes.create_string_buffer(n)
        got = ctypes.c_size_t()
        ok = k32.ReadProcessMemory(ctypes.c_void_p(self.h), ctypes.c_void_p(addr),
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

    def in_image(self, v):
        return v is not None and self.base <= v < self.base + self.size

    def heap_ptr(self, v):
        return v is not None and 0x10000 < v < 0x7FFFFFFFFFFF and self.u64(v) is not None


def fmt_matrix(m):
    return " ".join("%.3f" % v for v in m)


def find_matrix(L, inst, span, limit=3):
    """Locate row-major view matrices: unit-ish rotation rows, [15] == 1.0."""
    hits, off = [], 0
    while off + 0x40 <= span:
        v = L.f32(inst + off, 16)
        if v is None:
            break
        if (abs(v[15] - 1.0) < 0.001
                and 0.5 < abs(v[0]) < 1.5 and 0.5 < abs(v[5]) < 1.5
                and 0.5 < abs(v[10]) < 1.5
                and all(x == x and abs(x) < 1e6 for x in v)
                and abs(v[12]) < 4.0 and abs(v[13]) < 4.0 and abs(v[14]) < 4.0):
            hits.append((off, v))
        off += 4
    return hits[:limit]


def scan_entities(L, arr, stride, count=256):
    """How many of the first `count` slots look like real entities?"""
    ptrs, zero = [], 0
    for i in range(count):
        e = L.u64(arr + i * stride)
        if not e:
            zero += 1
            continue
        vt = L.u64(e)
        if L.in_image(vt):
            ptrs.append((i, e, vt))
        else:
            return None
    return ptrs, zero


def main():
    L = Live()
    out = []

    def p(s=""):
        out.append(s)

    p("# live probe  pid=%d  base=%#x  size=%#x" % (L.pid, L.base, L.size))

    p("")
    p("## entity list candidates (stride 8 / 0x20)")
    lists = []
    for rva in ENTITYLIST_C:
        slot = L.base + rva
        raw = L.u64(slot)
        line = "  rva=%#010x slot=%#x hold=%s" % (rva, slot, hex(raw) if raw is not None else "?")
        if not L.heap_ptr(raw):
            p(line + "   (not a readable pointer)")
            continue
        stride, found = None, None
        for st in (8, 0x20):
            r = scan_entities(L, raw, st, 256)
            if r and len(r[0]) >= 8:
                stride, found = st, r
                break
        if stride is None:
            p(line + "   (no coherent pointer array)")
            continue
        ptrs, zero = found
        p(line + "   entity_array=%#x stride=%#x valid=%d zero=%d" %
          (raw, stride, len(ptrs), zero))
        for i, e, vt in ptrs[:6]:
            p("      [%3d] %#x vtable=%#x(rva %#x)" % (i, e, vt, vt - L.base))
        lists.append((rva, raw, stride, ptrs))

    p("")
    p("## local player candidates")
    locals_ = []
    for rva in LOCAL_PLAYER:
        val = L.u64(L.base + rva)
        if not L.heap_ptr(val):
            p("  rva=%#010x hold=%s  (not a pointer)" % (rva, hex(val) if val is not None else "?"))
            continue
        vt = L.u64(val)
        p("  rva=%#010x -> ent=%#x vtable=%s" % (rva, val, hex(vt) if vt else "?"))
        for er, arr, st, ptrs in lists:
            hit = [i for i, e, _ in ptrs if e == val]
            if hit:
                p("      ALSO in entity list rva=%#010x -> slots %s" % (er, hit[:8]))
                locals_.append((rva, val, er, hit))

    p("")
    p("## other globals (sanity: readable pointer or small scalar)")
    for label, rvas in (("name_list", NAME_LIST), ("global_vars", GLOBAL_VARS),
                        ("local_handle", HANDLE_SIG), ("studio_hdr", STUDIO_HDR),
                        ("highlight", HIGHLIGHT)):
        for rva in rvas:
            q = L.u64(L.base + rva)
            p("  %-13s rva=%#010x qword=%s %s" %
              (label, rva, hex(q) if q is not None else "?",
               "IMAGE" if L.in_image(q) else ("heap" if L.heap_ptr(q) else "")))

    p("")
    p("## view render candidates")
    for rva in VIEW_RENDER:
        inst = L.u64(L.base + rva)
        if not L.heap_ptr(inst):
            p("  rva=%#010x -> not a pointer (%s)" % (rva, hex(inst) if inst is not None else "?"))
            continue
        vt = L.u64(inst)
        p("  rva=%#010x -> inst=%#x vtable=%s" % (rva, inst, hex(vt) if vt else "?"))
        for off, v in find_matrix(L, inst, 0x3000):
            p("      matrix @+%#06x %s" % (off, fmt_matrix(v)))

    p("")
    p("## entity struct: local player first 0x100 qwords (module pointers marked)")
    for rva, ent, er, hit in locals_[:1]:
        raw = L.read(ent, 0x400)
        if raw:
            for i in range(0, len(raw), 8):
                q = struct.unpack_from("<Q", raw, i)[0]
                tag = "IMAGE" if L.in_image(q) else ""
                p("  +%#05x %#018x %s" % (i, q, tag))

    path = os.path.join(HERE, "live1.txt")
    open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
    sys.stdout.write("\n".join(out) + "\n[written] %s\n" % path)


if __name__ == "__main__":
    main()
