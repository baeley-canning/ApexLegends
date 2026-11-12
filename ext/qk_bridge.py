r"""qk_bridge -- the existing gdrv3 MapK reader for real process memory.

The read primitive was positive-controlled on live physical frames that the
old MmMapIoSpace copy rejects. This locator searches ONLY the object pool tag
`Proc\0` and checks the actual _EPROCESS name and PID (PDB-verified current
host _KPROCESS.DirectoryTableBase is +0x28; alternate measured build +0x98).

Every raw PA read uses the real RAM interval set; table reads always use one
4KiB page. No new driver, process attach, process write or arbitrary frames.
The locator's verdict is a PE round-trip, not a plausible-looking qword.
"""
import ctypes as C
import os
import struct
import time

import gio
import dumplive as dl
import qk_va
import qk_gdrv_mapread

NAME = b"r5apex_dx12.exe"
IMAGE = 0xDFB8000


def find_pid():
    import subprocess, json
    out = subprocess.check_output([
        "powershell", "-NoProfile", "-Command",
        "Get-Process -Name r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id"],
        text=True, timeout=12)
    return [int(s.strip()) for s in out.splitlines() if s.strip().isdigit()]


def find_pid_toolhelp():
    class PE32(C.Structure):
        _fields_ = [("dwSize", C.c_ulong), ("cntUsage", C.c_ulong),
                    ("th32ProcessID", C.c_ulong),
                    ("th32DefaultHeapID", C.c_void_p),
                    ("th32ModuleID", C.c_ulong), ("cntThreads", C.c_ulong),
                    ("th32ParentProcessID", C.c_ulong),
                    ("pcPriClassBase", C.c_long), ("dwFlags", C.c_ulong),
                    ("szExeFile", C.c_wchar * 260)]
    k = C.WinDLL("kernel32", use_last_error=True)
    k.CreateToolhelp32Snapshot.restype = C.c_void_p
    snap = k.CreateToolhelp32Snapshot(2, 0)
    p = PE32()
    p.dwSize = C.sizeof(p)
    ok = k.Process32FirstW(C.c_void_p(snap), C.byref(p))
    found = []
    while ok:
        if p.szExeFile.lower() == NAME:
            found.append(int(p.th32ProcessID))
        ok = k.Process32NextW(C.c_void_p(snap), C.byref(p))
    k.CloseHandle(snap)
    return found


class ObjectScan:
    """Shared native Gio/MapK reader, one bounded Proc-tag-only scan."""
    def __init__(self):
        self.g = gio.Gio(chunk=0x1000)
        self.mapread = qk_gdrv_mapread.install(self.g)
        self.g.read_phys = self.mapread.read
        self.cache = {}

    def close(self):
        self.g.close()

    def scan(self, pid, budget=100.0):
        found = []
        start = time.time()
        for lo, hi in self.mapread.ranges:
            pa = lo
            while pa + 0x1000 <= hi:
                if time.time() - start > budget:
                    return found
                try:
                    buf = self.mapread.read(pa, 0x1000)
                except OSError:
                    pa += 0x1000
                    continue
                at = buf.find(b"Proc\0")
                if at >= 0:
                    for candidate in (at + 0xC, at + 0x10, at + 8):
                        for noff, toff, doff in ((0x338, 0, 0x28),
                                                (0x3A8, 0x70, 0x98)):
                            if candidate + noff + 15 > 0x1000:
                                continue
                            if buf[candidate+noff:candidate+noff+15] != b"r5apex_dx12.ex\0":
                                continue
                            if buf[candidate + toff] != 3:
                                continue
                            poff = 0x1D0 if noff == 0x338 else 0x240
                            if struct.unpack_from("<I", buf, candidate+poff)[0] != pid:
                                continue
                            dtb = struct.unpack_from("<Q", buf, candidate+doff)[0] & dl.MASK
                            if self.mapread.in_ram(dtb, 0x1000):
                                found.append((pa + candidate, dtb))
                pa += 0x1000
        return found

    def bind(self, pid, log, budget=100.0):
        """Return only a DTB/base whose PEB and full Apex PE resolve."""
        peb = qk_va._peb_va(pid)
        log("QUERY pid=%d PEB=%#x; guarded Proc-only scan" % (pid, peb or 0))
        for obj, dtb in self.scan(pid, budget):
            log("candidate object=%#x dtb=%#x" % (obj, dtb))
            try:
                rd = qk_va.Reader(self.g, dtb)
                raw = rd.read(peb + 0x10, 8)
                if not raw:
                    continue
                base = struct.unpack("<Q", raw)[0]
                page = rd.read(base, 0x1000)
                meta = dl.validate_pe(page) if page else None
                if not meta or meta["size"] != IMAGE:
                    continue
                self.dtb, self.base = dtb, base
                qk_va.save_cache(pid, dtb, base)
                log("RESULT: DTB=%#x base=%#x image_pa=%#x" %
                    (dtb, base, rd.page_pa(base)))
                return dtb, base
            except OSError as e:
                log("walk refused: %s" % e)
        log("RESULT: no accepted DTB/PE pair")
        return None