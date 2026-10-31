r"""physmem.py -- direct user-mode physical-memory access via \Device\PhysicalMemory.

No driver needed at all for this primitive: elevated callers open
\Device\PhysicalMemory (SECTION_MAP_READ|WRITE) and NtMapViewOfSection a
window of physical address space into our own process.  MsIo64.sys uses
exactly the same mechanism internally (worker 0x1090), so the technique is
known-good on this box.

Notes:
  * views are page-granular; we map 64 KiB-aligned blocks and keep them in a
    cache so the glow loop writes through a persistent mapping (in-process
    memcpy speed, no syscall per write).
  * a view shows whatever currently lives at that *physical frame*.  Game
    memory can migrate, so addresses are re-resolved every tick upstream;
    the cache only avoids repeated map/unmap syscalls within a burst.
"""
import ctypes
import struct
from ctypes import wintypes

ntdll = ctypes.WinDLL("ntdll", use_last_error=False)

SECTION_QUERY = 0x0001
SECTION_MAP_WRITE = 0x0002
SECTION_MAP_READ = 0x0004
SECTION_ALL_ACCESS = 0xF001F
PAGE_READWRITE = 0x04
PAGE_NOCACHE = 0x200
ViewShare = 1
BLOCK = 0x10000              # map granularity: 64 KiB aligned blocks


class UNICODE_STRING(ctypes.Structure):
    _fields_ = [("Length", wintypes.USHORT),
                ("MaximumLength", wintypes.USHORT),
                ("Buffer", ctypes.c_void_p)]


class OBJECT_ATTRIBUTES(ctypes.Structure):
    _fields_ = [("Length", ctypes.c_ulong),
                ("RootDirectory", ctypes.c_void_p),
                ("ObjectName", ctypes.POINTER(UNICODE_STRING)),
                ("Attributes", ctypes.c_ulong),
                ("SecurityDescriptor", ctypes.c_void_p),
                ("SecurityQualityOfService", ctypes.c_void_p)]


class IO_STATUS_BLOCK(ctypes.Structure):
    class _U(ctypes.Union):
        _fields_ = [("Status", ctypes.c_long), ("Pointer", ctypes.c_void_p)]
    _fields_ = [("Status", _U), ("Information", ctypes.c_ulonglong)]


class LARGE_INTEGER(ctypes.Structure):
    _fields_ = [("QuadPart", ctypes.c_longlong)]


def _us(s):
    buf = ctypes.create_unicode_buffer(s)
    u = UNICODE_STRING(len(s) * 2, (len(s) + 1) * 2,
                       ctypes.cast(buf, ctypes.c_void_p))
    # keep the buffer alive via the returned tuple
    return u, buf


ntdll.NtOpenSection.restype = ctypes.c_long
ntdll.NtOpenSection.argtypes = [ctypes.POINTER(ctypes.c_void_p), ctypes.c_ulong,
                                ctypes.POINTER(OBJECT_ATTRIBUTES)]
ntdll.NtMapViewOfSection.restype = ctypes.c_long
ntdll.NtMapViewOfSection.argtypes = [
    ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p),
    ctypes.c_size_t, ctypes.c_size_t, ctypes.POINTER(LARGE_INTEGER),
    ctypes.POINTER(ctypes.c_ulonglong), ctypes.c_ulong, ctypes.c_ulong,
    ctypes.c_ulong]
ntdll.NtUnmapViewOfSection.restype = ctypes.c_long
ntdll.NtUnmapViewOfSection.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
ntdll.NtClose.restype = ctypes.c_long
ntdll.NtClose.argtypes = [ctypes.c_void_p]

CURPROC = 0xFFFFFFFFFFFFFFFF   # (HANDLE)-1 = NtCurrentProcess


advapi32 = ctypes.WinDLL("advapi32", use_last_error=False)

TOKEN_ADJUST_PRIVILEGES = 0x0020
TOKEN_QUERY = 0x0008
SE_PRIVILEGE_ENABLED = 0x0002


class LUID(ctypes.Structure):
    _fields_ = [("LowPart", ctypes.c_ulong), ("HighPart", ctypes.c_long)]


class LUID_AND_ATTRIBUTES(ctypes.Structure):
    _fields_ = [("Luid", LUID), ("Attributes", ctypes.c_ulong)]


class TOKEN_PRIVILEGES(ctypes.Structure):
    _fields_ = [("PrivilegeCount", ctypes.c_ulong),
                ("Privileges", LUID_AND_ATTRIBUTES * 1)]


def enable_privilege(name):
    """Enable a privilege (e.g. SeLoadDriverPrivilege) in our token."""
    tok = ctypes.c_void_p()
    if not advapi32.OpenProcessToken(
            ctypes.c_void_p(-1).value, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY,
            ctypes.byref(tok)):
        return ctypes.get_last_error()
    luid = LUID()
    if not advapi32.LookupPrivilegeValueW(None, name, ctypes.byref(luid)):
        advapi32.CloseHandle(tok)
        return ctypes.get_last_error()
    tp = TOKEN_PRIVILEGES()
    tp.PrivilegeCount = 1
    tp.Privileges[0].Luid = luid
    tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED
    advapi32.AdjustTokenPrivileges(tok, False, ctypes.byref(tp), 0, None, None)
    err = ctypes.get_last_error()
    advapi32.CloseHandle(tok)
    return err


class PhysMem(object):
    def __init__(self):
        self.h = None
        self.views = {}          # block_base -> (base_va, size)
        self.priv_err = enable_privilege("SeLoadDriverPrivilege")
        u, buf = _us(r"\Device\PhysicalMemory")
        oa = OBJECT_ATTRIBUTES()
        oa.Length = ctypes.sizeof(oa)
        oa.ObjectName = ctypes.pointer(u)
        oa.Attributes = 0x200    # OBJ_CASE_INSENSITIVE
        h = ctypes.c_void_p(0)
        st = ntdll.NtOpenSection(ctypes.byref(h),
                                 SECTION_MAP_READ | SECTION_MAP_WRITE, ctypes.byref(oa))
        if st < 0:
            raise OSError(st, "NtOpenSection(\\Device\\PhysicalMemory) failed %#08x" % (st & 0xFFFFFFFF))
        self.h = h

    def map_block(self, block_base, size=BLOCK, nocache=False):
        """Map [block_base, block_base+size); both must be BLOCK-aligned."""
        hit = self.views.get(block_base)
        if hit:
            return hit[0]
        base = ctypes.c_void_p(0)
        off = LARGE_INTEGER(block_base)
        vs = ctypes.c_ulonglong(size)
        protect = (PAGE_READWRITE | PAGE_NOCACHE) if nocache else PAGE_READWRITE
        st = ntdll.NtMapViewOfSection(self.h, CURPROC,
                                      ctypes.byref(base), 0, 0,
                                      ctypes.byref(off), ctypes.byref(vs),
                                      ViewShare, 0, protect)
        if st < 0:
            raise OSError(st, "NtMapViewOfSection %#x failed %#08x"
                          % (block_base, st & 0xFFFFFFFF))
        self.views[block_base] = (base.value, vs.value)
        return base.value

    def map(self, pa, size):
        """Map a range spanning pa..pa+size; returns (base_va, off_in_view)."""
        if size > BLOCK:
            raise ValueError("map() covers one 64 KiB block; call map_block")
        blk = pa & ~(BLOCK - 1)
        base = self.map_block(blk)
        return base, pa - blk

    def read(self, pa, size):
        base, off = self.map(pa, size)
        return ctypes.string_at(base + off, size)

    def write(self, pa, data):
        base, off = self.map(pa, len(data))
        ctypes.memmove(base + off, bytes(data), len(data))

    def view_of(self, pa):
        """Persistent mapped pointer for pa (caller keeps the block cached)."""
        base, off = self.map(pa, 8)
        return base + off

    def close(self):
        for blk in list(self.views):
            base, _ = self.views.pop(blk)
            ntdll.NtUnmapViewOfSection(CURPROC, base)
        if self.h:
            ntdll.NtClose(self.h)
            self.h = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
