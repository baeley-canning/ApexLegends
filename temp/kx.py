"""kx.py -- user-mode client for the apexr kernel reader (kernel route).

Reads a process's memory through IOCTL_APEXR_READ (MmCopyVirtualMemory) and
walks its VADs through IOCTL_APEXR_QUERY (ZwQueryVirtualMemory), so a target
whose PROCESS_VM_READ was stripped by EAC's Ob callback is still readable.

usage:
    kx.py                  scan the running game for "Coupe"
    kx.py --selftest       read the first bytes of the game's image base
    kx.py --pid N --name S

If the driver is not loaded yet:  sc start apexr   (needs test signing on)
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct
import sys

DEVICE = r"\\.\apexr"
SVC = "apexr"
IOCTL_READ = 0x222000          # CTL_CODE(FILE_DEVICE_UNKNOWN,0x800,METHOD_BUFFERED,ANY)
IOCTL_QUERY = 0x222004         # CTL_CODE(FILE_DEVICE_UNKNOWN,0x801,METHOD_BUFFERED,ANY)
EXE = "r5apex_dx12.exe"

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
k32.CreateFileW.restype = wt.HANDLE
k32.CreateFileW.argtypes = [wt.LPCWSTR, wt.DWORD, wt.DWORD, ctypes.c_void_p,
                             wt.DWORD, wt.DWORD, wt.HANDLE]
k32.DeviceIoControl.argtypes = [wt.HANDLE, wt.DWORD, ctypes.c_void_p, wt.DWORD,
                                 ctypes.c_void_p, wt.DWORD,
                                 ctypes.POINTER(wt.DWORD), ctypes.c_void_p]
k32.DeviceIoControl.restype = wt.BOOL
k32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
k32.OpenProcess.restype = wt.HANDLE
k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                  ctypes.c_size_t,
                                  ctypes.POINTER(ctypes.c_size_t)]
k32.ReadProcessMemory.restype = wt.BOOL

MEM_COMMIT = 0x1000
PAGE_GUARD = 0x100
PAGE_NOACCESS = 0x01

out = []


def p(s=""):
    out.append(s)


def find_pid(exe):
    class PE32(ctypes.Structure):
        _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD),
                    ("th32ProcessID", wt.DWORD), ("th32DefaultHeapID", ctypes.c_size_t),
                    ("th32ModuleID", wt.DWORD), ("cntThreads", wt.DWORD),
                    ("th32ParentProcessID", wt.DWORD), ("pcPriClassBase", ctypes.c_long),
                    ("dwFlags", wt.DWORD), ("szExeFile", wt.WCHAR * 260)]

    snap = k32.CreateToolhelp32Snapshot(0x2, 0)
    pe = PE32()
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


class Reader:
    """Driver-backed process reader."""

    def __init__(self, pid):
        self.pid = pid
        self.h = k32.CreateFileW(DEVICE, 0xC0000000, 0, None, 3, 0, None)
        if not self.h or self.h == 0xFFFFFFFFFFFFFFFF:
            raise OSError("CreateFile(%s) failed err=%d (driver loaded?)"
                          % (DEVICE, ctypes.get_last_error()))

    def close(self):
        if self.h:
            k32.CloseHandle(self.h)
            self.h = None

    def _ioctl(self, code, req, outlen):
        ret = wt.DWORD(0)
        reqbuf = (ctypes.c_char * len(req)).from_buffer_copy(req)
        outb = (ctypes.c_char * outlen)()
        ok = k32.DeviceIoControl(self.h, code, reqbuf, len(req), outb, outlen,
                                 ctypes.byref(ret), None)
        return bool(ok), ctypes.get_last_error(), ret.value, bytes(outb)

    def read(self, addr, size):
        req = struct.pack("<IIQ", self.pid, size, addr)
        ok, err, got, data = self._ioctl(IOCTL_READ, req, size)
        if got:
            return data[:got], 0            # partial reads still useful
        return None, (err if not ok else 0)

    def query(self, addr):
        req = struct.pack("<IIQ", self.pid, 0, addr)
        ok, err, got, data = self._ioctl(IOCTL_QUERY, req, 0x30)
        if not ok or got < 0x30:
            return None, err
        base, alloc, aprot, part, size, state, protect, typ = \
            struct.unpack_from("<QQIIQIII", data, 0)
        return {"base": base, "alloc": alloc, "size": size, "state": state,
                "protect": protect, "type": typ}, 0

    def regions(self, low=0x10000, high=0x7FFFFFFEFFFF):
        """Walk mappings, hopping over address-space holes with exponentially
        growing probes.  A fixed 64 KB step would need ~2e9 IOCTLs to cross the
        128 TB user range; with this probe the walk costs a few thousand."""
        addr = low
        gap = 0x10000
        n = 0
        while addr < high and n < 2000000:
            info, _err = self.query(addr)
            n += 1
            if not info:
                addr += gap
                gap = min(gap * 2, 0x40000000)       # cap probes at 1 GB
                continue
            gap = 0x10000
            yield info
            addr = (max(info["base"], addr) + (info["size"] or 0x1000)
                    + 0xFFF) & ~0xFFF


def image_info(rd, base):
    """Parse the PE headers mapped at `base` through the driver and pull the
    CodeView PDB name out of the debug directory (identifies the module)."""
    data, _e = rd.read(base, 0x1000)
    if not data or len(data) < 0x200 or data[:2] != b"MZ":
        return None
    e = struct.unpack_from("<I", data, 0x3C)[0]
    if e + 0x100 > len(data) or data[e:e + 4] != b"PE\0\0":
        return None
    machine, nsec = struct.unpack_from("<HH", data, e + 4)
    magic = struct.unpack_from("<H", data, e + 24)[0]
    if magic != 0x20B:                       # PE32+ only
        return None
    sizeimg = struct.unpack_from("<I", data, e + 24 + 0x38)[0]
    imgbase = struct.unpack_from("<Q", data, e + 24 + 0x18)[0]
    ndir = struct.unpack_from("<I", data, e + 24 + 0x6C)[0]
    info = {"base": base, "image_base": imgbase, "size_image": sizeimg,
            "machine": machine, "sections": nsec, "pdb": None}
    if ndir > 6:
        dbg_rva, dbg_sz = struct.unpack_from("<II", data, e + 24 + 0x70 + 6 * 8)
        ent, _e2 = rd.read(base + dbg_rva, min(dbg_sz, 0x200)) if dbg_rva else (None, 0)
        for i in range(0, max(len(ent or b"") - 27, 0), 28):
            typ, szd, addr = struct.unpack_from("<III", ent, i + 12)
            if typ != 2 or not addr:        # 2 == CodeView
                continue
            cv, _e3 = rd.read(base + addr, min(max(szd, 64), 0x200))
            if cv and cv[:4] == b"RSDS" and len(cv) > 25:
                info["pdb"] = cv[24:].split(b"\0")[0].decode("latin-1")
                break
    return info


def main():
    pid = None
    name = "Coupe"
    for i, a in enumerate(sys.argv):
        if a == "--pid":
            pid = int(sys.argv[i + 1], 0)
        if a == "--name":
            name = sys.argv[i + 1]
    if pid is None:
        pid = find_pid(EXE)
    p("target %s pid=%s" % (EXE, pid))
    if not pid:
        return 1

    try:
        rd = Reader(pid)
    except OSError as e:
        p(str(e))
        return 1
    p("driver handle ok")

    if "--selftest" in sys.argv:
        best = None
        seen = 0
        for r in rd.regions():
            if r["type"] != 0x1000000 or r["state"] != MEM_COMMIT:
                continue
            if r["protect"] & 0x100:                  # PAGE_GUARD
                continue
            info = image_info(rd, r["base"])
            if not info:
                continue
            if best is None or info["size_image"] > best["size_image"]:
                best = info
            if info["pdb"] and "r5apex" in info["pdb"].lower():
                best = info
                break
            seen += 1
            if seen >= 40:
                break
        if not best:
            p("no readable MEM_IMAGE headers -> FAIL")
            rd.close()
            return 2
        p("image base=%#x size_image=%#x sections=%d machine=%#x"
          % (best["base"], best["size_image"], best["sections"], best["machine"]))
        p("pdb=%s" % (best["pdb"] or "(none - largest image chosen)"))
        if best["image_base"] != best["base"]:
            p("note: ASLR rebased (preferred %#x)" % best["image_base"])
        p("selftest PASS - parsed the target's PE headers over IOCTL 0x222000")

        h = k32.OpenProcess(0x10, False, pid)          # PROCESS_VM_READ
        if not h:
            p("baseline OpenProcess(VM_READ) failed err=%d -> EAC stripped it"
              % ctypes.get_last_error())
        else:
            got = ctypes.c_size_t(0)
            buf = (ctypes.c_char * 64)()
            ok = k32.ReadProcessMemory(h, ctypes.c_void_p(best["base"]), buf, 64,
                                       ctypes.byref(got))
            p("baseline ReadProcessMemory ok=%s read=%d err=%d"
              % (bool(ok), got.value, ctypes.get_last_error()))
            k32.CloseHandle(h)
        rd.close()
        return 0

    needle = [(name.encode("ascii"), "ascii"), (name.encode("utf-16-le"), "utf16")]
    total = 0
    hits = []
    for r in rd.regions():
        if r["state"] != MEM_COMMIT or (r["protect"] & PAGE_GUARD) \
                or (r["protect"] & 0xFF) == PAGE_NOACCESS:
            continue
        base, size = r["base"], min(r["size"], 0x4000000)
        total += size
        off = 0
        while off < size and len(hits) < 60:
            data, _err = rd.read(base + off, 0x10000)
            if data:
                for n, tag in needle:
                    idx = data.find(n)
                    if idx >= 0:
                        hits.append((base + off + idx, tag))
            off += 0x10000
    p("scanned %d MB, %d hit(s)" % (total // (1024 * 1024), len(hits)))
    for addr, tag in hits[:60]:
        p("  %#x %s" % (addr, tag))
    rd.close()
    return 0


if __name__ == "__main__":
    rc = main()
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "kx.txt")
    open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("\n".join(out))
    sys.exit(rc)
