"""open_probe.py -- figure out how gdrv3's \Device\GIOV3 can be opened.

CreateFileW("\\.\GIOV3", GENERIC_READ|GENERIC_WRITE) returns 5 (access denied).
That is either an SDDL restriction (IoCreateDeviceSecure / WDF SD) or an
exclusive-open collision.  Try every (access, share, flags) combination that
would still let us send DeviceIoControl, and report the process elevation.
"""
import ctypes
import os
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "open_probe.txt")

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
adv = ctypes.WinDLL("advapi32", use_last_error=True)

k32.CreateFileW.restype = wintypes.HANDLE
k32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                             wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD,
                             wintypes.HANDLE]
k32.GetCurrentProcess.restype = wintypes.HANDLE
adv.OpenProcessToken.restype = wintypes.BOOL
adv.OpenProcessToken.argtypes = [wintypes.HANDLE, wintypes.DWORD,
                                  ctypes.POINTER(wintypes.HANDLE)]
adv.GetTokenInformation.restype = wintypes.BOOL

TOKEN_QUERY = 0x0008
TokenElevation = 20
TokenIntegrityLevel = 25

lines = []
_fh = open(OUT, "w", encoding="utf-8")


def log(s=""):
    lines.append(s)
    _fh.write(s + "\n")
    _fh.flush()
    print(s)


def elevation():
    tok = wintypes.HANDLE()
    if not adv.OpenProcessToken(k32.GetCurrentProcess(), TOKEN_QUERY,
                                ctypes.byref(tok)):
        return "OpenProcessToken failed %d" % ctypes.get_last_error()
    buf = ctypes.create_string_buffer(64)
    ln = wintypes.DWORD(0)
    elev = -1
    if adv.GetTokenInformation(tok, TokenElevation, buf, 64, ctypes.byref(ln)):
        elev = ctypes.cast(buf, ctypes.POINTER(wintypes.DWORD))[0]
    rid = 0
    if adv.GetTokenInformation(tok, TokenIntegrityLevel, buf, 64,
                               ctypes.byref(ln)):
        sid = ctypes.cast(buf, ctypes.POINTER(ctypes.c_void_p))[0]
        if sid:
            cnt = ctypes.cast(ctypes.c_void_p(sid),
                              ctypes.POINTER(ctypes.c_ubyte))[1]
            rid = ctypes.cast(ctypes.c_void_p(sid + 8 + 4 * (cnt - 1)),
                              ctypes.POINTER(wintypes.DWORD))[0]
    k32.CloseHandle(tok)
    return "elevated=%s integrity_rid=%#x (0x2000=system 0x3000=medium 0x4000=high)" % (
        "yes" if elev == 1 else "no", rid)


k32.CloseHandle.argtypes = [wintypes.HANDLE]
OPEN_EXISTING = 3
INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value

ACCESS = [("0", 0x0000),
          ("SYNCHRONIZE", 0x00100000),
          ("READ", 0x80000000),
          ("WRITE", 0x40000000),
          ("READ|WRITE", 0xC0000000),
          ("R|W|SYNC", 0xC0100000)]
SHARE = [("none", 0), ("all", 0x7), ("rw", 0x3)]
FLAGS = [("normal", 0), ("overlapped", 0x40000000)]


def main():
    log("=== identity: %s" % elevation())
    log("=== \\\\.\\GIOV3 access matrix")
    winner = None
    for an, av in ACCESS:
        for sn, sv in SHARE:
            for fn, fv in FLAGS:
                ctypes.set_last_error(0)
                h = k32.CreateFileW(r"\\.\GIOV3", av, sv, None, OPEN_EXISTING,
                                    fv, None)
                if h and h != INVALID_HANDLE_VALUE:
                    ok = True
                    err = 0
                    k32.CloseHandle(h)
                else:
                    ok = False
                    err = ctypes.get_last_error()
                log("  access=%-11s share=%-4s flags=%-10s -> %s (%d)"
                    % (an, sn, fn, "OK" if ok else "fail", err))
                if ok and winner is None:
                    winner = (av, sv, fv)
    log("=== first working combo: %s" % (repr(winner) if winner
                                         else "none"))


try:
    main()
finally:
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
