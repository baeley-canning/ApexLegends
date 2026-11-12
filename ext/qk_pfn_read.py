r"""Native PFN mapping + current GIOV3 MapK. SeProfileSingleProcessPrivilege is
enabled on OUR token only where available for this documented query. Never
creates/changes driver or game state. Only a matching marker validates PFN.
"""
import ctypes as C
import struct


def enable_page_query_privilege():
    a = C.windll.advapi32
    k = C.windll.kernel32
    class Luid(C.Structure):
        _fields_ = [("low", C.c_ulong), ("high", C.c_long)]
    class Tp(C.Structure):
        _fields_ = [("count", C.c_ulong), ("privilege", Luid),
                    ("attributes", C.c_ulong)]
    k.GetCurrentProcess.restype = C.c_void_p
    tok = C.c_void_p()
    if not a.OpenProcessToken(k.GetCurrentProcess(), 0x28, C.byref(tok)):
        return C.get_last_error()
    luid = Luid()
    ok = a.LookupPrivilegeValueW(None, "SeProfileSingleProcessPrivilege", C.byref(luid))
    tp = Tp(1, luid, 2)
    ok = a.AdjustTokenPrivileges(tok, False, C.byref(tp), 0, None, None)
    C.windll.kernel32.CloseHandle(tok)
    return C.get_last_error() if not ok else 0


class PfnPolicy(C.Structure):
    _fields_ = [("version", C.c_uint32), ("magic", C.c_uint32),
                ("operation", C.c_uint32), ("data", C.c_void_p)]


def translate(va):
    buf = C.create_string_buffer(0xd8)
    struct.pack_into("<IIQ", buf, 0, 1, 0, 1)
    struct.pack_into("<Q", buf, 0xc0, va)
    q = PfnPolicy(1, 0x50695153, 6, C.addressof(buf))
    st = C.windll.ntdll.NtQuerySystemInformation(79, C.byref(q), 0xd8, None)
    return st & 0xffffffff, struct.unpack_from("<QQQ", buf, 0xc0)