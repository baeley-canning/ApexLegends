r"""h392 A/B permission check: documented user-mode read, not an injector.
Only PEB.ImageBaseAddress and one PE page of Apex. No attach, no new driver,
no WriteProcessMemory, no memory protection changes and no fallback search.
A refused access is reported -- it is never bypassed.
"""
import ctypes as C
import ctypes.wintypes as W
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "_h392_access.txt")
open(OUT, "w").close()
k32 = C.windll.kernel32
nt = C.windll.ntdll
k32.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
k32.OpenProcess.restype = W.HANDLE
k32.ReadProcessMemory.argtypes = [W.HANDLE, W.LPCVOID, W.LPVOID, C.c_size_t,
                                 C.POINTER(C.c_size_t)]
k32.ReadProcessMemory.restype = W.BOOL


class Basic(C.Structure):
    _fields_ = [("status", C.c_long), ("peb", C.c_void_p),
                ("affinity", C.c_size_t), ("priority", C.c_long),
                ("pid", C.c_size_t), ("parent", C.c_size_t)]


def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")


h = k32.OpenProcess(0x1000 | 0x0010, False, 14008)
say("=== h392 user-read A/B %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
say("type pointer=%s OpenProcess=%#x err=%d" % (W.HANDLE, h or 0,
                                                C.get_last_error()))
if not h:
    say("RESULT: query_vm_read_handle_refused")
    say("VERDICT: BLOCKED_USER_READ")
    sys.exit(3)
b = Basic()
n = C.c_ulong(0)
status = nt.NtQueryInformationProcess(h, 0, C.byref(b), C.sizeof(b),
                                      C.byref(n))
say("process_query status=0x%08X peb=%#x" % (status & 0xFFFFFFFF, b.peb or 0))
want = C.c_size_t(0)
raw = C.create_string_buffer(8)
ok = k32.ReadProcessMemory(h, C.c_void_p(b.peb + 0x10), raw, 8, C.byref(want))
err = C.get_last_error()
say("peb_read ok=%d bytes=%d err=%d data=%s" % (ok, want.value, err,
                                                raw.raw.hex()))
if ok and want.value == 8:
    base = struct.unpack("<Q", raw)[0]
    page = C.create_string_buffer(0x1000)
    got = C.c_size_t(0)
    ok2 = k32.ReadProcessMemory(h, C.c_void_p(base), page, 0x1000, C.byref(got))
    err2 = C.get_last_error()
    say("image_read base=%#x ok=%d bytes=%d err=%d mz=%r" %
        (base, ok2, got.value, err2, page.raw[:2]))
    say("RESULT: user_read=%s" % ("WORKS" if ok2 else "REFUSED_AT_IMAGE"))
    say("VERDICT: %s" % ("PASS_USER_READ" if ok2 else "PARTIAL"))
else:
    say("RESULT: peb_read_refused")
    say("VERDICT: BLOCKED_USER_READ")
k32.CloseHandle(h)