"""find_holder.py -- who holds \\Device\\GIOV3 open?

CreateFileW fails with ERROR_ACCESS_DENIED even for desired-access 0, which is
the signature of an exclusive open (WdfDeviceInitSetExclusive, or a WDF SDDL
that grants only SYSTEM/Administrators) rather than something we can fix with
different access rights.

Layout calibrated in dbg_handles.py (x64, stride 40):
    +0  PVOID     Object
    +8  ULONG_PTR UniqueProcessId
    +16 ULONG_PTR HandleValue
    +24 ULONG     GrantedAccess
    +28 USHORT    CreatorBackTraceIndex
    +30 USHORT    ObjectTypeIndex
    +32 ULONG     HandleAttributes

The File type index is taken from a handle we own (a temp file), so the scan
can never silently filter everything out.
"""
import ctypes
import msvcrt
import os
import threading
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "find_holder.txt")

ntdll = ctypes.WinDLL("ntdll")
k32 = ctypes.WinDLL("kernel32", use_last_error=True)
_fh = open(OUT, "w", encoding="utf-8")

STRIDE = 40
SystemExtendedHandleInformation = 64
PROCESS_DUP_HANDLE = 0x0040
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
DUPLICATE_SAME_ACCESS = 0x0002
STATUS_INFO_LENGTH_MISMATCH = -1073741820


class UNICODE_STRING(ctypes.Structure):
    _fields_ = [("Length", wintypes.USHORT),
                ("MaximumLength", wintypes.USHORT),
                ("Buffer", ctypes.c_void_p)]


ntdll.NtQueryObject.restype = ctypes.c_long
ntdll.NtQueryObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p,
                                 wintypes.ULONG, ctypes.POINTER(wintypes.ULONG)]
k32.GetFileType.restype = wintypes.DWORD
k32.GetFileType.argtypes = [wintypes.HANDLE]
FILE_TYPE_PIPE = 3
ntdll.NtQuerySystemInformation.restype = ctypes.c_long
ntdll.NtQuerySystemInformation.argtypes = [ctypes.c_int, ctypes.c_void_p,
                                           wintypes.ULONG,
                                           ctypes.POINTER(wintypes.ULONG)]
k32.OpenProcess.restype = wintypes.HANDLE
k32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
k32.DuplicateHandle.restype = wintypes.BOOL
k32.DuplicateHandle.argtypes = [wintypes.HANDLE, wintypes.HANDLE,
                                 wintypes.HANDLE,
                                 ctypes.POINTER(wintypes.HANDLE),
                                 wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
k32.GetCurrentProcess.restype = wintypes.HANDLE
k32.GetCurrentProcessId.restype = wintypes.DWORD
k32.CloseHandle.argtypes = [wintypes.HANDLE]
k32.QueryFullProcessImageNameW.restype = wintypes.BOOL
k32.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD,
                                            wintypes.LPWSTR,
                                            ctypes.POINTER(wintypes.DWORD)]


def log(s=""):
    _fh.write(s + "\n")
    _fh.flush()
    print(s)


def u32(at):
    return ctypes.cast(at, ctypes.POINTER(wintypes.ULONG))[0]


def u64(at):
    return ctypes.cast(at, ctypes.POINTER(ctypes.c_size_t))[0]


def u16(at):
    return ctypes.cast(at, ctypes.POINTER(wintypes.USHORT))[0]


def snapshot():
    """Full SYSTEM_HANDLE_INFORMATION_EX snapshot: (buf, count, base)."""
    size = 8 << 20
    while True:
        buf = ctypes.create_string_buffer(size)
        need = wintypes.ULONG(0)
        st = ntdll.NtQuerySystemInformation(SystemExtendedHandleInformation,
                                            buf, size, ctypes.byref(need))
        if st == STATUS_INFO_LENGTH_MISMATCH:
            size = max(need.value + 0x100000, size * 2)
            continue
        if st < 0:
            return None, "NtQuerySystemInformation -> %#x" % (st & 0xFFFFFFFF)
        return (buf, u64(ctypes.addressof(buf)),
                ctypes.addressof(buf) + 16), None


def file_type_index(tab, pid, hv):
    """ObjectTypeIndex of the \\File handle (pid, hv) we own.

    Calibrates the type filter from a handle we know is a file, so a wrong
    ObjectTypeIndex reading can never silently filter out every entry.
    """
    buf, n, base = tab
    for i in range(n):
        e = base + i * STRIDE
        if u64(e + 8) == pid and u64(e + 16) == hv:
            return u16(e + 30)
    return None


def query_name(handle):
    buf = ctypes.create_string_buffer(2048)
    ln = wintypes.ULONG(0)
    st = ntdll.NtQueryObject(handle, 1, buf, 2048, ctypes.byref(ln))
    if st < 0:
        return None
    us = ctypes.cast(buf, ctypes.POINTER(UNICODE_STRING)).contents
    if not us.Length or not us.Buffer:
        return ""
    return ctypes.wstring_at(us.Buffer, us.Length // 2)


def query_name_timed(handle, timeout=0.30):
    """NtQueryObject(ObjectNameInformation) blocks forever on some pipes.

    Run it on a daemon thread and give up after `timeout` so one wedged handle
    cannot stall the whole scan.
    """
    box = {}
    th = threading.Thread(target=lambda: box.setdefault("v", query_name(handle)),
                          daemon=True)
    th.start()
    th.join(timeout)
    return box.get("v")


def proc_name(pid):
    h = k32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not h:
        return "<OpenProcess %d>" % ctypes.get_last_error()
    try:
        b = ctypes.create_unicode_buffer(1024)
        m = wintypes.DWORD(1024)
        if k32.QueryFullProcessImageNameW(h, 0, b, ctypes.byref(m)):
            return b.value
        return "<QFPIN %d>" % ctypes.get_last_error()
    finally:
        k32.CloseHandle(h)


def main():
    me = k32.GetCurrentProcess()
    mepid = k32.GetCurrentProcessId()

    # Keep a known file handle open so the snapshot contains it.
    tmp = os.path.join(os.environ.get("TEMP", "."), "_ftidx.tmp")
    with open(tmp, "wb") as f:
        f.write(b"x")
    fh = open(tmp, "rb")
    hv = msvcrt.get_osfhandle(fh.fileno())

    tab, err = snapshot()
    if tab is None:
        log("snapshot failed: %s" % err)
        return
    buf, n, base = tab
    log("=== %d system handles" % n)

    tidx = file_type_index(tab, mepid, hv)
    fh.close()
    try:
        os.remove(tmp)
    except OSError:
        pass
    log("=== File ObjectTypeIndex = %s" % tidx)
    if tidx is None:
        log("calibration failed: own file handle not found in table")
        return

    hits = 0
    scanned = 0
    dup_ok = 0
    hung = 0
    pipes = 0
    named = 0
    samples = []
    procs = {}
    for i in range(n):
        e = base + i * STRIDE
        if u16(e + 30) != tidx:
            continue
        scanned += 1
        pid = u64(e + 8)
        hval = u64(e + 16)
        acc = u32(e + 24)
        if pid not in procs:
            procs[pid] = k32.OpenProcess(PROCESS_DUP_HANDLE, False, pid)
        ph = procs[pid]
        if not ph:
            continue
        dup = wintypes.HANDLE()
        ok = k32.DuplicateHandle(ph, wintypes.HANDLE(hval), me,
                                 ctypes.byref(dup), 0, False,
                                 DUPLICATE_SAME_ACCESS)
        if not ok:
            continue
        dup_ok += 1
        if k32.GetFileType(dup) == FILE_TYPE_PIPE:
            pipes += 1
            k32.CloseHandle(dup)
            continue
        nm = query_name_timed(dup)
        if nm is None:
            hung += 1
        if nm:
            named += 1
            if nm.upper().startswith("\\DEVICE\\") and len(samples) < 8:
                samples.append("pid=%-6d %s" % (pid, nm))
            up = nm.upper()
            if "GIOV3" in up or "GDRV" in up or "MSIO" in up:
                hits += 1
                log("  HIT pid=%-6d handle=%#-8x access=%#010x %s%s"
                    % (pid, hval, acc, nm, "  <== self" if pid == mepid else ""))
                log("      process=%s" % proc_name(pid))
        try:
            k32.CloseHandle(dup)
        except OSError:
            pass
    for ph in procs.values():
        if ph:
            k32.CloseHandle(ph)
    log("=== scanned %d file handles (%d dup'd, %d pipes skipped, "
        "%d name-query timeouts), %d hits"
        % (scanned, dup_ok, pipes, hung, hits))
    log("=== name resolution OK: %d/%d non-pipe dup'd handles returned a name"
        % (named, dup_ok - pipes))
    for s in samples:
        log("    sample device handle: %s" % s)
    if not hits:
        log("no handle named GIOV3/GDRV/MSIO exists system-wide")
        log("=> the access-denied is a DACL/SDDL restriction, not a collision")


try:
    main()
except Exception as exc:                                    # noqa: BLE001
    log("EXC %r" % (exc,))
finally:
    _fh.close()
