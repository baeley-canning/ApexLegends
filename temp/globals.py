"""globals.py -- resolve and LIVE-validate the globals the ESP needs.

Every offset in temp/dm32_fields.tsv is recovered *statically* from the image;
temp/offsets_static.txt holds *candidate* RVAs from byte signatures (entitylist_a
and entitylist_b MISSED).  Neither is proof.  This script is the proof: it reads
the running game and demands that the numbers agree with each other.

Checks, in order of trust:
  1. the entity-list slot must hold a heap pointer whose elements' first qword
     points back into the image (a vtable) -- that cannot happen by accident;
  2. cross-check: the local-player slot must hold an entity that is *also* in
     that array.  This is what makes the entity-list + local-player pair
     trustworthy;
  3. field probe: a candidate entity must satisfy several independent fields at
     once -- m_iHealth in 0..1000 AND m_iTeamNum in 0..64 AND m_localOrigin
     finite/inside map bounds AND m_vecViewOffset.z around eye height.  A wrong
     base or a wrong offset breaks at least one of them.

Elevation (this bit cost the first live probe its whole run)
----------------------------------------------------------
temp/h_access.txt: game elevated=True, shell elevated=False.  Consequently
OpenProcess(VM_READ) -> ERROR_ACCESS_DENIED (5) and only
QUERY_LIMITED_INFORMATION is granted.  ReadProcessMemory therefore needs an
*elevated* python:

    Start-Process -Verb RunAs ...\\python.exe temp\\globals.py

That is also why h_access.txt shows rpm_ok=0 err=87 on the query-only handle:
ERROR_INVALID_PARAMETER is what RPM returns when the handle lacks VM_READ.

Output: temp/globals.txt (stdout is unreliable in this terminal).
Exit code 0 = entity list and local player both validated.
"""
import ctypes
import ctypes.wintypes as wt
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = "r5apex_dx12.exe"
REPORT = os.path.join(HERE, "globals.txt")

# --- candidate globals (temp/offsets_static.txt, temp/probe_maps.txt) --------
ENTITYLIST_C = [0x0335d680, 0x03013c80, 0x02fca848, 0x09b9a720]
LOCAL_PLAYER = [0x03e779d0]
VIEW_RENDER = [0x04068440, 0x05a64cb8, 0x03353680, 0x05a64c48, 0x05a64c78,
               0x05a64c40]
GLOBAL_VARS = [0x03623ad0]

# --- candidate field offsets (temp/dm32_fields.tsv) -------------------------
F_LOCAL_ORIGIN = 0x18      # DT_BaseEntity.m_localOrigin  (vec3)
F_HEALTH = 0x330            # DT_Player.m_iHealth
F_TEAM = 0x340              # DT_BaseEntity.m_iTeamNum
F_MAXHEALTH = 0x470         # DT_Player.m_iMaxHealth
F_LIFESTATE = 0x698         # DT_Player.m_lifeState
F_VIEWOFFSET = 0x4C         # DT_BaseCombatCharacter.m_vecViewOffset (vec3)

k32 = ctypes.WinDLL("kernel32", use_last_error=True)


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD),
                ("th32ProcessID", wt.DWORD),
                ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
                ("th32ModuleID", wt.DWORD), ("cntThreads", wt.DWORD),
                ("th32ParentProcessID", wt.DWORD), ("pcPriClassBase", ctypes.c_long),
                ("dwFlags", wt.DWORD), ("szExeFile", wt.WCHAR * 260)]


class MODULEENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("th32ModuleID", wt.DWORD),
                ("th32ProcessID", wt.DWORD), ("GlblcntUsage", wt.DWORD),
                ("ProccntUsage", wt.DWORD),
                ("modBaseAddr", ctypes.POINTER(ctypes.c_byte)),
                ("modBaseSize", wt.DWORD), ("hModule", wt.HMODULE),
                ("szModule", wt.WCHAR * 256), ("szExePath", wt.WCHAR * 260)]


class Process:
    MASKS = [(0x1F0FFF, "ALL_ACCESS"), (0x0410, "VM_READ|QUERY_INFO"),
             (0x0010, "VM_READ")]

    def __init__(self, exe=EXE):
        self.pid = self._find_pid(exe)
        if not self.pid:
            raise OSError("%s is not running" % exe)
        self.handle, self.mask_name = None, None
        last = 0
        for mask, name in self.MASKS:
            h = k32.OpenProcess(mask, False, self.pid)
            if h:
                self.handle, self.mask_name = h, name
                break
            last = ctypes.get_last_error()
        if not self.handle:
            raise OSError("OpenProcess(%d) failed for every mask, last err=%d. "
                          "The game is elevated (temp/h_access.txt) -- run this "
                          "script elevated too." % (self.pid, last))
        self.base, self.size = self._module(exe)

    @staticmethod
    def _find_pid(exe):
        snap = k32.CreateToolhelp32Snapshot(0x2, 0)
        pe = PROCESSENTRY32W()
        pe.dwSize = ctypes.sizeof(pe)
        pid = None
        try:
            ok = k32.Process32FirstW(snap, ctypes.byref(pe))
            while ok:
                if pe.szExeFile.lower() == exe.lower():
                    pid = pe.th32ProcessID
                    break
                ok = k32.Process32NextW(snap, ctypes.byref(pe))
        finally:
            k32.CloseHandle(snap)
        return pid

    def _module(self, exe):
        """Main module base/size, with three independent sources.

        Toolhelp is the tidy way, but on the live game TH32CS_SNAPMODULE comes
        back refusing to name r5apex_dx12.exe (EAC unlinks the module list for
        non-whitelisted processes), so fall back to the PEB image base and
        finally the linker's preferred base.  Every candidate is verified
        against the PE headers in memory, so a wrong base cannot slip through.
        """
        base = self._module_toolhelp(exe)
        if base and self._pe_image(base):
            self.base_note = "toolhelp"
            return base, self._size
        base = self._module_peb()
        if base and self._pe_image(base):
            self.base_note = "peb"
            return base, self._size
        for base in (0x140000000,):
            if self._pe_image(base):
                self.base_note = "preferred base %#x (toolhelp+peb failed)" % base
                return base, self._size
        raise OSError("cannot locate %s image base (toolhelp=%s peb=%s)"
                      % (exe, self._toolhelp_note, self._peb_note))

    def _module_toolhelp(self, exe):
        self._toolhelp_note = "not tried"
        snap = k32.CreateToolhelp32Snapshot(0x8 | 0x10, self.pid)
        if snap in (None, -1, 0xFFFFFFFFFFFFFFFF):
            self._toolhelp_note = "snapshot err=%d" % ctypes.get_last_error()
            return None
        me = MODULEENTRY32W()
        me.dwSize = ctypes.sizeof(me)
        found, count = None, 0
        try:
            ok = k32.Module32FirstW(snap, ctypes.byref(me))
            while ok:
                count += 1
                if found is None and me.szModule.lower() == exe.lower():
                    found = ctypes.cast(me.modBaseAddr, ctypes.c_void_p).value
                    size = me.modBaseSize
                ok = k32.Module32NextW(snap, ctypes.byref(me))
        finally:
            k32.CloseHandle(snap)
        if found is None:
            self._toolhelp_note = "%d modules enumerated, err=%d" % (
                count, ctypes.get_last_error())
            return None
        self._size = size
        return found

    def _module_peb(self):
        """PEB->ImageBaseAddress via NtQueryInformationProcess, no toolhelp."""
        class PBI(ctypes.Structure):
            _fields_ = [("Reserved1", ctypes.c_void_p),
                        ("PebBaseAddress", ctypes.c_void_p),
                        ("Reserved2", ctypes.c_void_p * 2),
                        ("UniqueProcessId", ctypes.c_void_p),
                        ("Reserved3", ctypes.c_void_p)]
        self._peb_note = "not tried"
        try:
            ntdll = ctypes.WinDLL("ntdll")
        except OSError as exc:
            self._peb_note = str(exc)
            return None
        pbi = PBI()
        ret = ctypes.c_ulong(0)
        st = ntdll.NtQueryInformationProcess(self.handle, 0, ctypes.byref(pbi),
                                             ctypes.sizeof(pbi), ctypes.byref(ret))
        if st != 0 or not pbi.PebBaseAddress:
            self._peb_note = "status=%#x peb=%s" % (st, pbi.PebBaseAddress)
            return None
        base = self.u64(pbi.PebBaseAddress + 0x10)
        self._peb_note = "peb=%#x image=%s" % (pbi.PebBaseAddress,
                                                hex(base) if base else "?")
        return base

    def _pe_image(self, base):
        """True if base carries a PE header; sets self._size from SizeOfImage."""
        head = self.read(base, 0x400)
        if not head or head[:2] != b"MZ":
            return False
        e_lfanew = struct.unpack_from("<I", head, 0x3C)[0]
        if e_lfanew + 0x60 > len(head) or head[e_lfanew:e_lfanew + 4] != b"PE\0\0":
            return False
        size = struct.unpack_from("<I", head, e_lfanew + 24 + 56)[0]
        if not (0x100000 <= size <= 0x40000000):
            return False
        self._size = size
        return True

    # ---- raw reads --------------------------------------------------------
    def read(self, addr, n):
        if not addr:
            return None
        buf = ctypes.create_string_buffer(n)
        got = ctypes.c_size_t(0)
        ok = k32.ReadProcessMemory(self.handle, ctypes.c_void_p(addr), buf, n,
                                   ctypes.byref(got))
        if not ok or got.value != n:
            return None
        return buf.raw

    def u64(self, addr):
        b = self.read(addr, 8)
        return struct.unpack("<Q", b)[0] if b else None

    def u32(self, addr):
        b = self.read(addr, 4)
        return struct.unpack("<I", b)[0] if b else None

    def u8(self, addr):
        b = self.read(addr, 1)
        return b[0] if b else None

    # ---- predicates -------------------------------------------------------
    def in_image(self, p):
        return bool(p) and self.base <= p < self.base + self.size

    def heap_ptr(self, p):
        if not p or p < 0x10000 or p >= 0x7FFFFFFFFFFF or self.in_image(p):
            return False
        return self.read(p, 8) is not None


def sane_vec3(raw):
    if raw is None or len(raw) < 12:
        return None
    x, y, z = struct.unpack("<fff", raw[:12])
    for v in (x, y, z):
        if not math.isfinite(v) or abs(v) > 40000.0:
            return None
    if x == 0.0 and y == 0.0 and z == 0.0:
        return None
    return (x, y, z)


def probe(p, ent):
    """Read every candidate field off one entity and score the agreement."""
    raw = p.read(ent, 0x700) or b""
    if len(raw) < F_LIFESTATE + 1:
        return None

    def g(off, n):
        return raw[off:off + n] if off + n <= len(raw) else None

    def i32(off):
        b = g(off, 4)
        return struct.unpack("<i", b)[0] if b else None

    origin = sane_vec3(g(F_LOCAL_ORIGIN, 12))
    voff = sane_vec3(g(F_VIEWOFFSET, 12))
    health, team, maxhp = i32(F_HEALTH), i32(F_TEAM), i32(F_MAXHEALTH)
    life = raw[F_LIFESTATE] if g(F_LIFESTATE, 1) else None

    score = 0
    score += 1 if health is not None and 0 <= health <= 1000 else 0
    score += 1 if team is not None and 0 <= team <= 64 else 0
    score += 1 if origin is not None else 0
    score += 1 if voff is not None and 20.0 <= abs(voff[2]) <= 120.0 else 0
    score += 1 if maxhp is not None and 0 <= maxhp <= 2000 else 0
    score += 1 if life in (0, 1, 2) else 0
    return {"health": health, "maxhp": maxhp, "team": team, "life": life,
            "origin": origin, "voff": voff, "score": score}


def scan_array(p, arr, stride, limit=256):
    """Collect (index, entity, vtable) for entries whose vtable is in-image."""
    out, zero = [], 0
    for i in range(limit):
        ent = p.u64(arr + i * stride)
        if not ent:
            zero += 1
            continue
        if not p.heap_ptr(ent):
            continue
        vt = p.u64(ent)
        if p.in_image(vt):
            out.append((i, ent, vt))
    return out, zero


def find_matrices(p, inst, span=0x3000):
    """16-float windows on a 16-byte grid whose magnitudes look like a
    projection/view matrix (finite, some zeros, sane scale)."""
    raw = p.read(inst, span)
    if not raw:
        return []
    hits = []
    for off in range(0, len(raw) - 64, 16):
        v = struct.unpack_from("<16f", raw, off)
        if not all(math.isfinite(x) for x in v):
            continue
        if not (0.001 < abs(v[15]) < 1000.0):
            continue
        zeros = sum(1 for x in v if x == 0.0)
        big = max(abs(x) for x in v)
        if zeros < 2 or big > 1e5:
            continue
        hits.append((off, v))
    return hits


def fmt_vec(v):
    return "-" if not v else "(%.1f, %.1f, %.1f)" % v


def write(out):
    text = "\n".join(out) + "\n"
    with open(REPORT, "w", encoding="utf-8") as fh:
        fh.write(text)
    sys.stdout.write(text)
def main():
    out = []

    def p(s=""):
        out.append(s)

    try:
        pr = Process()
    except OSError as exc:
        p("FAIL %s" % exc)
        write(out)
        return 1

    p("# globals probe  pid=%d  handle=%s  base=%#x (via %s)  size=%#x"
      % (pr.pid, pr.mask_name, pr.base, pr.base_note, pr.size))
    p("# toolhelp module list: %s" % pr._toolhelp_note)
    p("# peb: %s" % pr._peb_note)

    # -- 1. entity list ----------------------------------------------------
    p("")
    p("## entity list candidates")
    lists = []
    for rva in ENTITYLIST_C:
        slot = pr.base + rva
        val = pr.u64(slot)
        p("  rva=%#010x hold=%s" % (rva, hex(val) if val is not None else "?"))
        if not pr.heap_ptr(val):
            p("      not a heap pointer")
            continue
        got = False
        for label, arr in (("", val), ("+8", val + 8), ("+0x10", val + 0x10)):
            if got:
                break
            for stride in (8, 0x20):
                found, zero = scan_array(pr, arr, stride)
                if len(found) >= 8:
                    p("      array=%s%#x stride=%#x entities=%d zero=%d"
                      % (label, arr, stride, len(found), zero))
                    lists.append((rva, arr, stride, found))
                    got = True
                    break
    if not lists:
        p("  (no coherent pointer array -- entity list still unresolved)")

    # -- 2. local player ---------------------------------------------------
    p("")
    p("## local player candidates")
    local = None
    for rva in LOCAL_PLAYER:
        val = pr.u64(pr.base + rva)
        line = "  rva=%#010x -> %s" % (rva, hex(val) if val is not None else "?")
        if not pr.heap_ptr(val):
            p(line + "   (not a heap pointer)")
            continue
        vt = pr.u64(val)
        p(line + "   vtable=%s" % (hex(vt) if vt else "?"))
        for er, arr, stride, found in lists:
            hits = [i for i, e, _ in found if e == val]
            if hits:
                p("      ALSO in array rva=%#010x slots %s" % (er, hits[:8]))
                local = val

    # -- 3. field probe ----------------------------------------------------
    for rva, arr, stride, found in lists[:1]:
        p("")
        p("## field probe: array rva=%#010x stride=%#x (%d entities)"
          % (rva, stride, len(found)))
        p("  %-4s %-14s %6s %6s %6s %5s  %-24s %-20s %s"
          % ("idx", "entity", "hp", "max", "team", "life", "origin",
             "viewoff", "score"))
        sane = 0
        for idx, ent, _vt in found[:24]:
            f = probe(pr, ent)
            if not f:
                continue
            sane += 1 if f["score"] >= 5 else 0
            p("  %-4d %#014x %6s %6s %6s %5s  %-24s %-20s %d/6"
              % (idx, ent, f["health"], f["maxhp"], f["team"], f["life"],
                 fmt_vec(f["origin"]), fmt_vec(f["voff"]), f["score"]))
        p("  entities with score>=5/6: %d" % sane)

    # -- 4. local player dump (angles live somewhere in here) --------------
    if local:
        p("")
        p("## local player %#x -- non-zero qwords, pointers tagged" % local)
        raw = pr.read(local, 0x800) or b""
        for i in range(0, len(raw), 8):
            q = struct.unpack_from("<Q", raw, i)[0]
            if q == 0:
                continue
            if pr.in_image(q):
                p("  +%#05x %#014x IMAGE rva=%#x" % (i, q, q - pr.base))
            elif 0x10000 < q < 0x7FFFFFFFFFFF and pr.read(q, 8):
                p("  +%#05x %#014x heap" % (i, q))

    # -- 5. view render ----------------------------------------------------
    p("")
    p("## view render candidates")
    for rva in VIEW_RENDER:
        inst = pr.u64(pr.base + rva)
        if not pr.heap_ptr(inst):
            p("  rva=%#010x -> %s (not a heap pointer)"
              % (rva, hex(inst) if inst is not None else "?"))
            continue
        vt = pr.u64(inst)
        p("  rva=%#010x -> inst=%#x vtable=%s"
          % (rva, inst, ("%#x (rva %#x)" % (vt, vt - pr.base)) if vt else "?"))
        mats = find_matrices(pr, inst)
        p("      matrix-like windows: %d" % len(mats))
        for off, v in mats[:6]:
            p("      @+%#06x " % off + " ".join("%9.4f" % x for x in v))

    p("")
    p("## global_vars sanity")
    for rva in GLOBAL_VARS:
        q = pr.u64(pr.base + rva)
        p("  rva=%#010x qword=%s %s" % (rva, hex(q) if q is not None else "?",
                                        "IMAGE" if pr.in_image(q) else ""))

    p("")
    ok = bool(lists) and local is not None
    p("RESULT entity_list=%s local_player=%s"
      % (("rva %#x" % lists[0][0]) if lists else "UNRESOLVED",
         ("%#x" % local) if local else "UNRESOLVED"))
    write(out)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

