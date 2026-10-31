"""dbg_handles.py -- calibrate SYSTEM_HANDLE_INFORMATION(_EX) layout.

Opens a file, remembers its handle value, then locates that handle in the
system handle table and prints the surrounding dwords.  Whatever offset holds
our known pid / handle / file type index is the real layout, so find_holder.py
cannot silently skip every entry again.
"""
import ctypes
import os
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "dbg_handles.txt")

ntdll = ctypes.WinDLL("ntdll")
k32 = ctypes.WinDLL("kernel32", use_last_error=True)
_fh = open(OUT, "w", encoding="utf-8")


def log(s=""):
    _fh.write(s + "\n")
    _fh.flush()


ntdll.NtQuerySystemInformation.restype = ctypes.c_long
ntdll.NtQuerySystemInformation.argtypes = [ctypes.c_int, ctypes.c_void_p,
                                           wintypes.ULONG,
                                           ctypes.POINTER(wintypes.ULONG)]
k32.GetCurrentProcessId.restype = wintypes.DWORD
k32.CloseHandle.argtypes = [wintypes.HANDLE]


def query(cls, cap):
    buf = ctypes.create_string_buffer(cap)
    need = wintypes.ULONG(0)
    st = ntdll.NtQuerySystemInformation(cls, buf, cap, ctypes.byref(need))
    return st, buf, need.value


def u32(at):
    return ctypes.cast(at, ctypes.POINTER(wintypes.ULONG))[0]


def u64(at):
    return ctypes.cast(at, ctypes.POINTER(ctypes.c_size_t))[0]


def main():
    tmp = os.path.join(os.environ.get("TEMP", "."), "_dbgh.tmp")
    open(tmp, "wb").write(b"x")
    f = open(tmp, "rb")
    h0 = f.fileno()
    msph = ctypes.cast(f.fileno(), ctypes.c_void_p).value      # not the handle!
    # real OS handle for the C runtime fd:
    k32.GetOSFHandle = k32._handle  # noqa: SLF001
    import msvcrt
    hv = msvcrt.get_osfhandle(h0)
    pid = k32.GetCurrentProcessId()
    log("pid=%d  crt fd=%d  os handle=%#x" % (pid, h0, hv))

    st, buf, need = query(16, 8 << 20)
    log("class16 status=%#x need=%#x cap=%#x" % (st & 0xFFFFFFFF, need, 8 << 20))
    if st >= 0:
        n = min(u32(ctypes.addressof(buf)), 0x10000)
        log("class16 count=%d stride=32 -> %#x bytes used" % (n, n * 32))
        base = ctypes.addressof(buf) + 8
        found = 0
        for i in range(n):
            e = base + i * 32
            ep = u64(e)
            eh = ctypes.cast(e + 10, ctypes.POINTER(wintypes.USHORT))[0]
            if ep == pid and eh == (hv & 0xFFFF) and found < 3:
                found += 1
                log("  match @%d: pid=%#x type=%d flags=%d handle=%#x obj=%#x acc=%#x"
                    % (i, ep, ctypes.cast(e + 8, ctypes.POINTER(ctypes.c_ubyte))[0],
                       ctypes.cast(e + 9, ctypes.POINTER(ctypes.c_ubyte))[0],
                       eh, u64(e + 16), u32(e + 24)))
        log("class16 matches=%d" % found)

    st, buf, need = query(64, 16 << 20)
    log("class64 status=%#x need=%#x" % (st & 0xFFFFFFFF, need))
    if st < 0:
        return
    n = u64(ctypes.addressof(buf))
    log("class64 count=%d" % n)
    base = ctypes.addressof(buf) + 16
    for stride in (40, 48):
        found = 0
        for i in range(min(n, 200000)):
            e = base + i * stride
            if u64(e + 8) != pid:
                continue
            if u64(e + 16) != hv:
                continue
            found += 1
            dumps = " ".join("%d:%#x" % (o, u32(e + o)) for o in range(24, stride, 4))
            log("  stride=%d match @%d  tail dwords: %s" % (stride, i, dumps))
        log("  stride=%d matches=%d" % (stride, found))

    f.close()
    try:
        os.remove(tmp)
    except OSError:
        pass


try:
    main()
except Exception as exc:                                    # noqa: BLE001
    log("EXC %r" % (exc,))
finally:
    _fh.close()
