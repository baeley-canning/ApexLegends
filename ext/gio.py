r"""gio.py -- transport layer for the glow-only Apex ESP.

All kernel access goes through the third-party driver \\.\GIOV3 (gdrv3.sys).
No own driver is used: apexdrv/apexr never passed test-signing, and this device
is the only live transport on this box.

Primitive inventory (RE'd from YccDrvv3.dll wrappers + gdrv3.sys, status live):
  0xC3502014 read    in  {u64 pa; u32 size; u32 pad; void* dst}   [VERIFIED]
                     -> memcpy(dst, MmMapIoSpace(pa, size), size)
  0xC3502004 map     in  {u64 pa; u64 size} -> {u64 va; u64 ?}    [gate G2]
                     persistent user mapping of physical memory
  0xC3502008 unmap   in  {u64 va; u64 size}
  0xC3502019 mapK    in  same as read; out {u64 kva; u64 ?}       [gate G7]
  0xC3502800 kalloc  in  {u32 size} -> {u64 va; u64 pa}           [gate G4]
  0xC3502804 kfree   in  {u64 va; u64 ?}
  0xC3502808 physwr  in  {u64 arg2; u64 arg1; u32 arg3}           [gate G5]
                     wrapper YCC_MapMem_Copy_Userbuf_To_Phys(rcx=a, rdx=b,
                     r8d=n) packs the in-buffer as (b, a, n)
  0xC350280C trans   in  {u64 va} -> {u64 pa}                     [gate G3]
                     wrapper YCC_TranslateLinsToPhys(va, &out_pa)
  0xC3502400 decoy   echoes in->phys into out, ignores dst        [known]

Hard rules carried over from temp/drv/physread.py:
  * device DACL is D:P(A;;GA;;;SY)(A;;GA;;;BA) -> must be elevated
  * the driver maps raw physical pages without validating backing RAM, so an
    unbacked PA read bugchecks the machine: everything we touch goes through
    is_ram() or came out of a successful translate/alloc/page-walk.
"""
import ctypes
import struct
import time
from ctypes import wintypes

DEVICE = r"\\.\GIOV3"
PAGE = 0x1000

IOCTL_READ = 0xC3502014
IOCTL_MAP_EX = 0xC3502004
IOCTL_UNMAP = 0xC3502008
IOCTL_MAP_K = 0xC3502019
IOCTL_ALLOC = 0xC3502800
IOCTL_FREE = 0xC3502804
IOCTL_COPY_UP = 0xC3502808
IOCTL_TRANSLATE = 0xC350280C

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3
MEM_COMMIT = 0x1000
MEM_RESERVE = 0x2000
MEM_RELEASE = 0x8000
PAGE_READWRITE = 0x04

kernel32.CreateFileW.restype = wintypes.HANDLE
kernel32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                 wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD,
                                 wintypes.HANDLE]
kernel32.DeviceIoControl.restype = wintypes.BOOL
kernel32.DeviceIoControl.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPVOID,
                                     wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD,
                                     ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
kernel32.VirtualAlloc.restype = wintypes.LPVOID
kernel32.VirtualAlloc.argtypes = [wintypes.LPVOID, ctypes.c_size_t, wintypes.DWORD,
                                  wintypes.DWORD]
kernel32.VirtualFree.restype = wintypes.BOOL
kernel32.VirtualFree.argtypes = [wintypes.LPVOID, ctypes.c_size_t, wintypes.DWORD]
kernel32.VirtualLock.restype = wintypes.BOOL
kernel32.VirtualLock.argtypes = [wintypes.LPVOID, ctypes.c_size_t]
kernel32.VirtualUnlock.restype = wintypes.BOOL
kernel32.VirtualUnlock.argtypes = [wintypes.LPVOID, ctypes.c_size_t]
kernel32.CloseHandle.restype = wintypes.BOOL
kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.GetPhysicallyInstalledSystemMemory.restype = wintypes.BOOL
kernel32.GetPhysicallyInstalledSystemMemory.argtypes = [
    ctypes.POINTER(ctypes.c_ulonglong)]

INVALID_HANDLE = ctypes.c_void_p(-1).value


def installed_ram_bytes():
    kb = ctypes.c_ulonglong(0)
    if kernel32.GetPhysicallyInstalledSystemMemory(ctypes.byref(kb)):
        return kb.value * 1024
    return 0


def alloc_locked(size):
    p = kernel32.VirtualAlloc(None, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE)
    if not p:
        raise OSError("VirtualAlloc failed err=%d" % ctypes.get_last_error())
    kernel32.VirtualLock(p, size)
    return p


class Gio(object):
    """One device handle + a scratch landing buffer for phys reads."""

    def __init__(self, path=DEVICE, chunk=PAGE, map_cache_pages=64):
        self.path = path
        self.chunk = chunk
        self.h = kernel32.CreateFileW(path, GENERIC_READ | GENERIC_WRITE, 0,
                                      None, OPEN_EXISTING, 0, None)
        if not self.h or self.h == INVALID_HANDLE:
            raise OSError(ctypes.get_last_error(),
                          "CreateFileW %s failed (need elevation)" % path)
        self.dst = kernel32.VirtualAlloc(None, chunk, MEM_COMMIT | MEM_RESERVE,
                                         PAGE_READWRITE)
        if not self.dst:
            raise OSError("VirtualAlloc scratch failed")
        kernel32.VirtualLock(self.dst, chunk)
        self.ram_top = installed_ram_bytes()
        self.map_cache = {}          # page_pa -> (va, size)
        self.map_cache_max = map_cache_pages
        self.stats = {}              # ioctl -> [count, seconds]

    # -- low level ---------------------------------------------------------
    def _ioctl(self, code, in_buf, out_len, out_hint=64):
        ib = ctypes.create_string_buffer(bytes(in_buf), max(len(in_buf), 1))
        ob = ctypes.create_string_buffer(max(out_len, out_hint, 1))
        got = wintypes.DWORD(0)
        t0 = time.perf_counter()
        ok = kernel32.DeviceIoControl(self.h, code, ib, len(in_buf), ob,
                                      out_len, ctypes.byref(got), None)
        dt = time.perf_counter() - t0
        st = self.stats.setdefault(code, [0, 0.0])
        st[0] += 1
        st[1] += dt
        if not ok:
            return False, ctypes.get_last_error(), b"", got.value
        return True, 0, ob.raw[:got.value], got.value

    # -- read (verified primitive) ------------------------------------------
    def read_phys(self, pa, size):
        out = bytearray()
        left = size
        cur = pa
        while left:
            n = min(left, self.chunk)
            ib = struct.pack("<QIIQ", cur & 0xFFFFFFFFFFFFFFFF, n, 0, self.dst)
            ok, err, _, _ = self._ioctl(IOCTL_READ, ib, 0)
            if not ok:
                raise OSError(err, "phys read %#x+%#x failed" % (cur, n))
            out += ctypes.string_at(self.dst, n)
            cur += n
            left -= n
        return bytes(out)

    def u16(self, pa):
        return struct.unpack("<H", self.read_phys(pa, 2))[0]

    def u32(self, pa):
        return struct.unpack("<I", self.read_phys(pa, 4))[0]

    def u64(self, pa):
        return struct.unpack("<Q", self.read_phys(pa, 8))[0]

    # -- map / unmap (write path candidate) ----------------------------------
    def map_phys(self, pa, size):
        ib = struct.pack("<QQ", pa, size)
        ok, err, ob, got = self._ioctl(IOCTL_MAP_EX, ib, 0x10)
        if not ok:
            raise OSError(err, "map_phys %#x+%#x failed" % (pa, size))
        if got < 8:
            raise OSError("map_phys returned short info %d" % got)
        va = struct.unpack_from("<QQ", ob)[0]
        if not va:
            raise OSError("map_phys %#x+%#x -> va=0" % (pa, size))
        return va

    def unmap(self, va, size):
        ib = struct.pack("<QQ", va, size)
        ok, err, _, _ = self._ioctl(IOCTL_UNMAP, ib, 0)
        if not ok:
            raise OSError(err, "unmap %#x failed" % va)

    def map_page_cached(self, pa):
        """Persistent mapping of one page, cached (the glow loop rewrites the
        same highlight pages every frame; map/unmap per write would dominate)."""
        page = pa & ~0xFFF
        hit = self.map_cache.get(page)
        if hit:
            return hit[0] + (pa - page)
        va = self.map_phys(page, PAGE)
        self.map_cache[page] = (va, PAGE)
        if len(self.map_cache) > self.map_cache_max:
            old = next(iter(self.map_cache))     # FIFO eviction
            ova, osz = self.map_cache.pop(old)
            try:
                self.unmap(ova, osz)
            except OSError:
                pass
        return va + (pa - page)

    # -- write via mapping ----------------------------------------------------
    def write_phys(self, pa, data):
        """Write bytes at a physical address by mapping the page user-mode and
        memcpying.  Coherency must be proven by gate G6 before trusting this."""
        data = bytes(data)
        buf = (ctypes.c_ubyte * len(data)).from_buffer_copy(data)
        off = 0
        while off < len(data):
            page = (pa + off) & ~0xFFF
            within = (pa + off) - page
            chunk = min(PAGE - within, len(data) - off)
            va = self.map_page_cached(page)
            ctypes.memmove(va + within, ctypes.byref(buf, off), chunk)
            off += chunk

    # -- probes (measured, not assumed) ---------------------------------------
    def translate(self, va):
        """0xC350280C: {u64 va} -> {u64 pa}.  Returns (ok, pa_or_err)."""
        ib = struct.pack("<Q", va & 0xFFFFFFFFFFFFFFFF)
        ok, err, ob, got = self._ioctl(IOCTL_TRANSLATE, ib, 8)
        if not ok:
            return False, err
        if got < 8:
            return False, "short info %d" % got
        return True, struct.unpack_from("<Q", ob)[0]

    def kernel_alloc(self, size):
        """0xC3502800: {u32 size} -> {u64 va; u64 pa} (field meaning measured)."""
        ib = struct.pack("<I", size)
        ok, err, ob, got = self._ioctl(IOCTL_ALLOC, ib, 0x10)
        if not ok:
            return False, err, None
        if got < 0x10:
            return False, "short info %d" % got, None
        a, b = struct.unpack_from("<QQ", ob)
        return True, 0, (a, b)

    def kernel_free(self, a, b=0):
        ib = struct.pack("<QQ", a, b)
        ok, err, _, _ = self._ioctl(IOCTL_FREE, ib, 0)
        return ok, err

    def copy_user_to_phys(self, a, b, size):
        """0xC3502808: wrapper packs in-buffer as (rdx, rcx, r8d) = (b, a, size).
        Role assignment of a/b is decided empirically by gate G5."""
        ib = struct.pack("<QQI4x", b & 0xFFFFFFFFFFFFFFFF,
                         a & 0xFFFFFFFFFFFFFFFF, size)
        ok, err, _, _ = self._ioctl(IOCTL_COPY_UP, ib, 0)
        return ok, err

    def map_kernel(self, pa, size, dst_va):
        """0xC3502019: same in-struct as read, out {u64 kva; u64 ?}."""
        ib = struct.pack("<QIIQ", pa, size, 0, dst_va)
        ok, err, ob, got = self._ioctl(IOCTL_MAP_K, ib, 0x10)
        if not ok:
            return False, err, None
        if got < 8:
            return False, "short info %d" % got, None
        return True, 0, struct.unpack_from("<Q", ob)[0]

    # -- safety ---------------------------------------------------------------
    def is_ram(self, pa):
        """Conservative RAM check for pages whose validity was not derived from
        page tables (page-table PAs are RAM by construction)."""
        if self.ram_top and pa >= self.ram_top:
            return False
        if pa < 0xA0000:             # legacy low memory: IVT/BDA/EBDA fine
            return True
        if pa < 0x100000:            # VGA/ROM hole
            return False
        return True

    def read_phys_checked(self, pa, size):
        if not self.is_ram(pa):
            raise OSError("refusing non-RAM PA %#x" % pa)
        return self.read_phys(pa, size)

    # -- lifetime --------------------------------------------------------------
    def close(self):
        for page in list(self.map_cache):
            va, size = self.map_cache.pop(page)
            try:
                self.unmap(va, size)
            except OSError:
                pass
        if self.dst:
            kernel32.VirtualUnlock(self.dst, self.chunk)
            kernel32.VirtualFree(self.dst, 0, MEM_RELEASE)
            self.dst = None
        if self.h:
            kernel32.CloseHandle(self.h)
            self.h = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def stat_line(self, code):
        n, t = self.stats.get(code, [0, 0.0])
        if not n:
            return "%#010x: unused" % code
        return "%#010x: %4d calls, %6.2f us/call" % (code, n, t * 1e6 / n)
