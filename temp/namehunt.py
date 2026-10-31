"""namehunt.py -- find a player name in the live game and walk back to the player.

Player ESP needs players, not the entity tree.  The cheapest proof that a
candidate array really holds players is a *known* name: find that name in the
process, then find who points at the string.  Whatever owns the pointer is the
player object family, and its neighbours are the rest of the lobby.

Two things make this script unusual:

  1. reads may be blocked.  diag5/diag6 measured: OpenProcess(0x1fffff) works,
     ntdll!NtReadVirtualMemory -> 0xC000000D for every mask, while
     NtReadVirtualMemoryEx -> 0xC0000022 and NtQueryVirtualMemory works.  A
     user-mode ntdll hook explains that mix, so the third primitive here is a
     hand-built `syscall` stub whose SSN is parsed out of *on-disk* ntdll (the
     disk copy cannot be patched).  If the stub reads and ntdll does not, the
     hook is user mode and the stub is the way around it.
  2. names are UTF-16LE, often twice (a padded engine buffer plus a
     null-terminated copy), so both UTF-16LE and ASCII are searched, and every
     hit is reported with the bytes around it.

Output: temp/namehunt.txt (stdout is unreliable in this terminal).
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = "r5apex_dx12.exe"
REPORT = os.path.join(HERE, "namehunt.txt")
NAMES = ["Coupe", "SIRSH4GNASTY"]

CHUNK = 0x400000          # 4 MiB read window
OVERLAP = 0x400            # so a name straddling a chunk edge is still found

MEM_COMMIT, MEM_IMAGE, MEM_MAPPED, MEM_PRIVATE = 0x1000, 0x1000000, 0x40000, 0x20000
PAGE_GUARD = 0x100
READABLE = (0x02, 0x04, 0x06, 0x08, 0x20, 0x40, 0x80)

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
ntdll = ctypes.WinDLL("ntdll")

out = []


def p(s=""):
    out.append(s)


class MBI(ctypes.Structure):
    _fields_ = [("BaseAddress", ctypes.c_ulonglong),
                ("AllocationBase", ctypes.c_ulonglong),
                ("AllocationProtect", wt.DWORD), ("__a1", wt.DWORD),
                ("RegionSize", ctypes.c_ulonglong),
                ("State", wt.DWORD), ("Protect", wt.DWORD),
                ("Type", wt.DWORD), ("__a2", wt.DWORD)]


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD),
                ("th32ProcessID", wt.DWORD),
                ("th32DefaultHeapID", ctypes.c_size_t),
                ("th32ModuleID", wt.DWORD), ("cntThreads", wt.DWORD),
                ("th32ParentProcessID", wt.DWORD),
                ("pcPriClassBase", ctypes.c_long), ("dwFlags", wt.DWORD),
                ("szExeFile", wt.WCHAR * 260)]


k32.VirtualQueryEx.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.POINTER(MBI),
                                ctypes.c_size_t]
k32.VirtualQueryEx.restype = ctypes.c_size_t
k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                   ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
k32.ReadProcessMemory.restype = wt.BOOL
k32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
k32.OpenProcess.restype = wt.HANDLE

ntdll.NtReadVirtualMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                       ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
ntdll.NtReadVirtualMemory.restype = ctypes.c_long


def find_pid(exe):
    snap = k32.CreateToolhelp32Snapshot(0x2, 0)
    pe = PROCESSENTRY32W()
    pe.dwSize = ctypes.sizeof(pe)
    try:
        ok = k32.Process32FirstW(snap, ctypes.byref(pe))
        while ok:
            if pe.szExeFile.lower() == exe.lower():
                return pe.th32ProcessID
            ok = k32.Process32NextW(snap, ctypes.byref(pe))
    finally:
        k32.CloseHandle(snap)
    return None



# --------------------------------------------------------------------------
# SSN parsed out of the on-disk ntdll (a file cannot be inline-hooked)
# --------------------------------------------------------------------------
def _sections(data):
    e = struct.unpack_from("<I", data, 0x3C)[0]
    if data[e:e + 4] != b"PE\0\0":
        return [], 0
    nt = e + 4
    nsec = struct.unpack_from("<H", data, nt + 2)[0]          # NumberOfSections
    optsz = struct.unpack_from("<H", data, nt + 16)[0]        # SizeOfOptionalHeader
    opt = nt + 20
    sh = opt + optsz
    secs = []
    for i in range(nsec):
        vsize = struct.unpack_from("<I", data, sh + i * 40 + 8)[0]
        vaddr, rsize, rptr = struct.unpack_from("<III", data, sh + i * 40 + 12)
        secs.append((vaddr, max(vsize, rsize), rptr))
    return secs, opt


def _off(secs, rva):
    for va, sz, rp in secs:
        if va <= rva < va + sz:
            return rva - va + rp
    return None


def disk_export(dll_path, fname):
    """(ssn, bytes[0:24]) of an Nt* export as stored on disk, else (None, None)."""
    with open(dll_path, "rb") as f:
        data = f.read()
    secs, opt = _sections(data)
    if not secs:
        return None, None
    magic = struct.unpack_from("<H", data, opt)[0]
    ddoff = opt + (0x70 if magic == 0x20B else 0x60)
    edir_rva = struct.unpack_from("<I", data, ddoff)[0]
    eoff = _off(secs, edir_rva)
    if eoff is None:
        return None, None
    nfun, nname = struct.unpack_from("<II", data, eoff + 20)[:2]
    aoff = eoff + struct.unpack_from("<I", data, eoff + 28)[0] - edir_rva
    noff = eoff + struct.unpack_from("<I", data, eoff + 32)[0] - edir_rva
    for i in range(nname):
        nrva = struct.unpack_from("<I", data, noff + 4 * i)[0]
        npos = _off(secs, nrva)
        if npos is None:
            continue
        nm = data[npos:data.index(b"\0", npos)].decode("latin1")
        if nm != fname:
            continue
        ordi = struct.unpack_from("<H", data, noff + 4 * nname + 2 * i)[0]
        frva = struct.unpack_from("<I", data, aoff + 4 * ordi)[0]
        fpos = _off(secs, frva)
        if fpos is None:
            return None, None
        blk = data[fpos:fpos + 24]
        for j in range(len(blk) - 4):
            if blk[j] == 0xB8:                      # mov eax, imm32
                return struct.unpack_from("<I", blk, j + 1)[0], blk
        return None, blk
    return None, None


class Syscall:
    """mov r10,rcx ; mov eax,ssn ; syscall ; ret -- inside our own RWX page."""

    def __init__(self):
        self.cache = {}
        k32.VirtualAlloc.restype = ctypes.c_void_p
        k32.VirtualAlloc.argtypes = [ctypes.c_void_p, ctypes.c_size_t, wt.DWORD,
                                      wt.DWORD]

    def stub(self, ssn):
        if ssn not in self.cache:
            mem = k32.VirtualAlloc(None, 0x1000, 0x3000, 0x40)   # COMMIT|RESERVE RWX
            code = b"\x4c\x8b\xd1\xb8" + struct.pack("<I", ssn) + b"\x0f\x05\xc3"
            ctypes.memmove(mem, code, len(code))
            proto = ctypes.CFUNCTYPE(ctypes.c_long, ctypes.c_void_p,
                                     ctypes.c_void_p, ctypes.c_void_p,
                                     ctypes.c_size_t, ctypes.c_void_p,
                                     ctypes.c_size_t)          # 6 args: Ex needs them
            self.cache[ssn] = proto(mem)
        return self.cache[ssn]


class Reader:
    """RPM first, then ntdll, then a raw syscall stub.  First one that works wins."""

    def __init__(self, pid):
        self.pid = pid
        self.h = None
        self.hq = None
        self.acc = None
        for acc in (0x1FFFFF, 0x1F0FFF, 0x438, 0x410, 0x10, 0x1000):
            h = k32.OpenProcess(acc, False, pid)
            if h:
                self.h, self.acc = h, acc
                break
        self.mode = "none"
        self.sys = Syscall()
        self.ssn, self.disk_blk = disk_export(
            os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                         "System32", "ntdll.dll"), "NtReadVirtualMemory")

    def _rpm(self, addr, n):
        buf = ctypes.create_string_buffer(n)
        got = ctypes.c_size_t(0)
        if k32.ReadProcessMemory(self.h, ctypes.c_void_p(addr), buf, n,
                                 ctypes.byref(got)) and got.value:
            return buf.raw[:got.value]
        return None

    def _nt(self, addr, n):
        buf = ctypes.create_string_buffer(n)
        got = ctypes.c_size_t(0)
        st = ntdll.NtReadVirtualMemory(self.h, ctypes.c_void_p(addr), buf, n,
                                        ctypes.byref(got))
        return (buf.raw[:got.value] if got.value else None), st & 0xFFFFFFFF

    def _stub(self, addr, n):
        if self.ssn is None:
            return None, 0xDEAD
        buf = ctypes.create_string_buffer(n)
        got = ctypes.c_size_t(0)
        st = self.sys.stub(self.ssn)(self.h, ctypes.c_void_p(addr), buf, n,
                                     ctypes.byref(got), 0)
        return (buf.raw[:got.value] if got.value else None), st & 0xFFFFFFFF

    def read(self, addr, n):
        order = [(self._rpm, "rpm"), (self._nt, "nt"), (self._stub, "syscall")]
        if self.mode != "none":
            order.sort(key=lambda t: t[1] != self.mode)
        for fn, name in order:
            r = fn(addr, n)
            if isinstance(r, tuple):
                r = r[0]
            if r:
                self.mode = name
                return r
        return None

    def u64(self, addr):
        raw = self.read(addr, 8)
        return struct.unpack("<Q", raw)[0] if raw and len(raw) == 8 else None



# --------------------------------------------------------------------------
# address space
# --------------------------------------------------------------------------
def regions(rd):
    mbi = MBI()
    h = rd.hq or rd.h
    addr, acc = 0x10000, []
    while addr < 0x7FFFFFFEFFFF:
        if not k32.VirtualQueryEx(h, ctypes.c_void_p(addr), ctypes.byref(mbi),
                                   ctypes.sizeof(mbi)):
            break
        if (mbi.State == MEM_COMMIT
                and mbi.Type in (MEM_PRIVATE, MEM_IMAGE, MEM_MAPPED)
                and (mbi.Protect & 0xFF) in READABLE
                and not (mbi.Protect & PAGE_GUARD)):
            acc.append((mbi.BaseAddress, mbi.RegionSize, mbi.Type))
        nxt = mbi.BaseAddress + mbi.RegionSize
        if nxt <= addr:
            break
        addr = nxt
    return acc


def chunks(rd, base, size):
    """(addr, bytes) windows of CHUNK+OVERLAP, so names on an edge still match."""
    off = 0
    while off < size:
        n = min(CHUNK + OVERLAP, size - off)
        raw = rd.read(base + off, n)
        if raw:
            yield base + off, raw
        off += CHUNK


def image_base(rd, regs):
    """First MEM_IMAGE region whose DOS/PE headers parse -- that is the exe."""
    for base, _size, typ in regs:
        if typ != MEM_IMAGE:
            continue
        hdr = rd.read(base, 0x400)
        if not hdr or hdr[:2] != b"MZ":
            continue
        e = struct.unpack_from("<I", hdr, 0x3C)[0]
        if 0 < e < 0x300 and hdr[e:e + 4] == b"PE\0\0":
            return base
    return 0


# --------------------------------------------------------------------------
# hooks
# --------------------------------------------------------------------------
def disk_export_rva(dll_path, fname):
    with open(dll_path, "rb") as f:
        data = f.read()
    secs, opt = _sections(data)
    if not secs:
        return None
    magic = struct.unpack_from("<H", data, opt)[0]
    edir = struct.unpack_from("<I", data, opt + (0x70 if magic == 0x20B else 0x60))[0]
    eoff = _off(secs, edir)
    if eoff is None:
        return None
    nname = struct.unpack_from("<I", data, eoff + 24)[0]
    aoff = eoff + struct.unpack_from("<I", data, eoff + 28)[0] - edir
    noff = eoff + struct.unpack_from("<I", data, eoff + 32)[0] - edir
    for i in range(nname):
        nrva = struct.unpack_from("<I", data, noff + 4 * i)[0]
        npos = _off(secs, nrva)
        if npos is None:
            continue
        if data[npos:data.index(b"\0", npos)].decode("latin1") == fname:
            ordi = struct.unpack_from("<H", data, noff + 4 * nname + 2 * i)[0]
            return struct.unpack_from("<I", data, aoff + 4 * ordi)[0]
    return None


def hook_census(rd, regs):
    """Compare the game's ntdll!NtReadVirtualMemory stub with the file copy."""
    path = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                        "System32", "ntdll.dll")
    with open(path, "rb") as f:
        hdr = f.read(0x400)
    e = struct.unpack_from("<I", hdr, 0x3C)[0]
    stamp = struct.unpack_from("<I", hdr, e + 8)[0]
    size = struct.unpack_from("<I", hdr, e + 24 + 0x38)[0]
    rva = disk_export_rva(path, "NtReadVirtualMemory")
    p("  disk ntdll: stamp=%#x sizeofimage=%#x NtRVM rva=%s"
      % (stamp, size, hex(rva) if rva else "?"))
    found = None
    for base, _s, typ in regs:
        if typ != MEM_IMAGE:
            continue
        h = rd.read(base, 0x400)
        if not h or h[:2] != b"MZ":
            continue
        e2 = struct.unpack_from("<I", h, 0x3C)[0]
        if not (0 < e2 < 0x300) or h[e2:e2 + 4] != b"PE\0\0":
            continue
        if (struct.unpack_from("<I", h, e2 + 8)[0] == stamp
                and struct.unpack_from("<I", h, e2 + 24 + 0x38)[0] == size):
            found = base
            break
    if not found:
        p("  game ntdll: NOT FOUND (mapped copy unreadable?)")
        return
    p("  game ntdll base: %#x" % found)
    if not rva:
        return
    mem = rd.read(found + rva, 24)
    if not mem:
        p("  stub bytes unreadable")
        return
    p("  in-memory: %s" % mem.hex(" "))
    p("  on-disk  : %s" % (rd.disk_blk.hex(" ") if rd.disk_blk else "?"))
    same = rd.disk_blk and mem[:len(rd.disk_blk)] == rd.disk_blk[:len(mem)]
    p("  verdict  : %s" % ("clean" if same else "PATCHED"))



# --------------------------------------------------------------------------
# scanning
# --------------------------------------------------------------------------
def scan_names(rd, regs, names):
    pats = []
    for nm in names:
        pats.append((nm, "utf16", nm.encode("utf-16-le")))
        pats.append((nm, "ascii", nm.encode()))
    hits, total = [], 0
    for base, size, typ in regs:
        for caddr, raw in chunks(rd, base, size):
            total += len(raw)
            low = raw.lower()
            for nm, kind, pat in pats:
                i = low.find(pat.lower())
                while i >= 0:
                    hits.append({"addr": caddr + i, "name": nm, "kind": kind,
                                 "type": typ,
                                 "ctx": raw[max(0, i - 0x20):i + 0x30]})
                    if len(hits) > 400:
                        return hits, total
                    i = low.find(pat.lower(), i + 1)
    return hits, total


def scan_ptrs(rd, regs, targets):
    """Find qwords equal to any target address (i.e. who points at the name)."""
    try:
        import numpy as np
    except ImportError:
        np = None
    keys = sorted(targets)
    arr = np.array(keys, dtype="<u8") if np is not None else None
    found = []
    for base, size, _typ in regs:
        for caddr, raw in chunks(rd, base, size):
            if np is None:
                for i in range(0, len(raw) - 8, 8):
                    if struct.unpack_from("<Q", raw, i)[0] in targets:
                        found.append((caddr + i,
                                      struct.unpack_from("<Q", raw, i)[0]))
                continue
            n = (len(raw) // 8) * 8
            a = np.frombuffer(raw[:n], dtype="<u8")
            for i in np.flatnonzero(np.isin(a, arr)):
                found.append((caddr + int(i) * 8, int(a[i])))
    return found


def dump(rd, addr, n, img, names):
    raw = rd.read(addr, n)
    if not raw:
        return ["      <unreadable>"]
    lines = []
    for i in range(0, len(raw) - 7, 8):
        q = struct.unpack_from("<Q", raw, i)[0]
        if q == 0:
            continue
        tag = ""
        if img and img <= q < img + 0x20000000:
            tag = "IMAGE rva=%#x" % (q - img)
        elif q in names:
            tag = "NAME %s" % names[q]
        elif 0x10000 < q < 0x7FFFFFFFFFFF and rd.read(q, 8):
            tag = "heap"
        seg = raw[i:i + 8]
        txt = ""
        if all(0x20 <= c < 0x7F for c in seg):
            txt = "  '" + seg.decode("latin1") + "'"
        lines.append("      +%#05x %#014x %s%s" % (i, q, tag, txt))
    for enc, lbl in (("utf-16-le", "utf16"), ("latin1", "ascii")):
        try:
            s = raw.decode(enc, "ignore")
        except Exception:
            continue
        for w in s.split("\0"):
            w = w.strip()
            if 3 <= len(w) <= 40 and all(c.isprintable() for c in w):
                lines.append("      %s string: %r" % (lbl, w))
    return lines[:40]



# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
def is_elevated():
    adv = ctypes.WinDLL("advapi32", use_last_error=True)
    tok = wt.HANDLE()
    if not adv.OpenProcessToken(k32.GetCurrentProcess(), 0x8, ctypes.byref(tok)):
        return None
    val = wt.DWORD(0)
    n = wt.DWORD(0)
    adv.GetTokenInformation(tok, 20, ctypes.byref(val), ctypes.sizeof(val),
                            ctypes.byref(n))
    k32.CloseHandle(tok)
    return bool(val.value)


def write():
    with open(REPORT, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")


def matrix(rd, addr):
    p("  --- primitive matrix at %#x ---" % addr)
    buf = ctypes.create_string_buffer(0x40)
    got = ctypes.c_size_t(0)
    ok = k32.ReadProcessMemory(rd.h, ctypes.c_void_p(addr), buf, 0x40,
                               ctypes.byref(got))
    p("    ReadProcessMemory   ok=%d err=%d got=%d"
      % (bool(ok), ctypes.get_last_error(), got.value))
    got = ctypes.c_size_t(0)
    st = ntdll.NtReadVirtualMemory(rd.h, ctypes.c_void_p(addr), buf, 0x40,
                                   ctypes.byref(got))
    p("    ntdll NtRead        status=%#010x got=%d" % (st & 0xFFFFFFFF, got.value))
    got = ctypes.c_size_t(0)
    if rd.ssn is not None:
        st = rd.sys.stub(rd.ssn)(rd.h, ctypes.c_void_p(addr), buf, 0x40,
                                  ctypes.byref(got), 0)
        p("    raw syscall ssn=%#x  status=%#010x got=%d bytes=%s"
          % (rd.ssn, st & 0xFFFFFFFF, got.value,
             buf.raw[:min(16, got.value)].hex(" ")))
    else:
        p("    raw syscall stub     unavailable (ssn parse failed)")


def main():
    names = sys.argv[1:] or NAMES
    pid = find_pid(EXE)
    p("## process")
    p("  exe=%s pid=%s shell_elevated=%s" % (EXE, pid, is_elevated()))
    if not pid:
        write()
        return 1

    rd = Reader(pid)
    p("  OpenProcess acc=%s handle=%s err=%d"
      % (hex(rd.acc) if rd.acc else "?", rd.h or 0, ctypes.get_last_error()))
    p("  ReadVirtualMemory ssn=%s disk=%s"
      % (hex(rd.ssn) if rd.ssn else "?",
         rd.disk_blk.hex(" ") if rd.disk_blk else "?"))
    if not rd.h:
        write()
        return 1

    regs = regions(rd)
    if not regs:
        hq = k32.OpenProcess(0x400, False, pid)
        p("  VirtualQueryEx returned nothing; QUERY_INFORMATION handle=%s" % hq)
        rd.hq = hq
        regs = regions(rd)
    total_mb = sum(s for _b, s, _t in regs) / (1024.0 * 1024.0)
    p("  readable regions=%d  total=%.0f MB" % (len(regs), total_mb))
    if not regs:
        write()
        return 1

    p("")
    p("## primitives")
    matrix(rd, regs[0][0])
    p("")
    p("## ntdll hook census")
    hook_census(rd, regs)

    img = image_base(rd, regs)
    p("")
    p("## image base: %#x" % img)

    p("")
    p("## name scan: %s" % ", ".join(names))
    hits, seen = scan_names(rd, regs, names)
    p("  scanned %.0f MB, %d hits" % (seen / (1024.0 * 1024.0), len(hits)))

    targets = {}
    for h in hits:
        targets.setdefault(h["addr"], h["name"])

    dump_cache = {}
    for h in hits[:24]:
        p("")
        p("  hit %s %s at %#x (%s)"
          % (h["name"], h["kind"], h["addr"],
             {MEM_PRIVATE: "private", MEM_IMAGE: "image",
              MEM_MAPPED: "mapped"}[h["type"]]))
        for line in dump(rd, h["addr"] - 0x20, 0x80, img, targets):
            p(line)

    if not hits:
        p("  (nothing found -- wrong name, or the reads are lying)")
        write()
        return 1

    p("")
    p("## who points at those strings (%d targets)" % len(targets))
    refs = scan_ptrs(rd, regs, targets)
    p("  references: %d" % len(refs))
    for raddr, val in refs[:40]:
        p("  ref @ %#014x -> %#x (%s)  [%#x]"
          % (raddr, val, targets.get(val, "?"), raddr & ~0xFFF))
    if len(refs) > 1:
        uniq = sorted(set(r for r, _v in refs))
        gaps = sorted(set(uniq[i + 1] - uniq[i] for i in range(len(uniq) - 1)))
        p("  distinct refs=%d  smallest stride=%#x"
          % (len(uniq), gaps[0] if gaps else 0))

    for raddr, val in refs[:8]:
        p("")
        p("  structure around ref %#x (-> %s)" % (raddr, targets.get(val, "?")))
        for line in dump(rd, raddr - 0x40, 0x180, img, targets):
            p(line)

    p("")
    p("## read mode used: %s" % rd.mode)
    write()
    return 0


if __name__ == "__main__":
    sys.exit(main())
