"""h_access.py -- which OpenProcess masks does the LIVE game actually grant?

live_run.txt shows OpenProcess(11996, 0x410) -> ERROR_ACCESS_DENIED (5), so the
old live_probe.py never produced a single reading.  Before any ESP code is worth
writing, find out *which* access right is being refused and whether the refusal
is elevation (game started as admin, shell is not) or the anti-cheat stripping
handles.

Prints one line per mask, plus the elevation state of both tokens.
Output also lands in temp/h_access.txt because run_commands stdout is unreliable.
"""
import ctypes
import ctypes.wintypes as wt
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = "r5apex_dx12.exe"

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
adv = ctypes.WinDLL("advapi32", use_last_error=True)

MASKS = [
    ("QUERY_LIMITED_INFORMATION", 0x1000),
    ("VM_READ", 0x0010),
    ("VM_READ|QUERY_INFORMATION", 0x0410),
    ("VM_READ|QUERY_LIMITED", 0x1010),
    ("VM_READ|VM_WRITE|QUERY", 0x0438),
    ("ALL_ACCESS", 0x1F0FFF),
]

TOKEN_QUERY = 0x0008
TokenElevation = 20


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD),
                ("th32ProcessID", wt.DWORD),
                ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
                ("th32ModuleID", wt.DWORD), ("cntThreads", wt.DWORD),
                ("th32ParentProcessID", wt.DWORD), ("pcPriClassBase", ctypes.c_long),
                ("dwFlags", wt.DWORD), ("szExeFile", wt.WCHAR * 260)]


def find_pid(name):
    snap = k32.CreateToolhelp32Snapshot(0x2, 0)
    pe = PROCESSENTRY32W()
    pe.dwSize = ctypes.sizeof(pe)
    pid = None
    try:
        ok = k32.Process32FirstW(snap, ctypes.byref(pe))
        while ok:
            if pe.szExeFile.lower() == name.lower():
                pid = pe.th32ProcessID
                break
            ok = k32.Process32NextW(snap, ctypes.byref(pe))
    finally:
        k32.CloseHandle(snap)
    return pid


def elevation(pid):
    """True/False for token elevation, None if the token cannot even be opened."""
    h = k32.OpenProcess(0x1000, False, pid)  # QUERY_LIMITED_INFORMATION
    if not h:
        return None, ctypes.get_last_error()
    tok = wt.HANDLE()
    if not adv.OpenProcessToken(h, TOKEN_QUERY, ctypes.byref(tok)):
        err = ctypes.get_last_error()
        k32.CloseHandle(h)
        return None, err
    val = wt.DWORD(0)
    n = wt.DWORD(0)
    ok = adv.GetTokenInformation(tok, TokenElevation, ctypes.byref(val),
                                 ctypes.sizeof(val), ctypes.byref(n))
    k32.CloseHandle(tok)
    k32.CloseHandle(h)
    return (bool(val.value) if ok else None), 0


def main():
    out = []
    p = out.append
    pid = find_pid(EXE)
    p("self     pid=%d" % os.getpid())
    p("target   %s pid=%s" % (EXE, pid))
    me, err = elevation(os.getpid())
    p("self     elevated=%s (err=%d)" % (me, err))
    if not pid:
        p("game is not running")
        return finish(out)
    el, err = elevation(pid)
    p("game     elevated=%s (err=%d)" % (el, err))
    p("")
    p("## OpenProcess masks")
    for label, mask in MASKS:
        h = k32.OpenProcess(mask, False, pid)
        if h:
            p("  %-28s %#08x  OK    handle=%#x" % (label, mask, h))
            k32.CloseHandle(h)
        else:
            p("  %-28s %#08x  FAIL  err=%d" % (label, mask, ctypes.get_last_error()))
    p("")
    p("## read test with whatever handle we can get")
    for label, mask in MASKS:
        h = k32.OpenProcess(mask, False, pid)
        if not h:
            continue
        buf = ctypes.create_string_buffer(8)
        got = ctypes.c_size_t(0)
        # module base is not known yet; try the image base read via the PEB-less
        # trick: read at 0x140000000 (default image base for this exe)
        ok = k32.ReadProcessMemory(h, ctypes.c_void_p(0x140000000),
                                   buf, 8, ctypes.byref(got))
        p("  mask %-28s rpm_ok=%d got=%d err=%d mz=%s" %
          (label, bool(ok), got.value, ctypes.get_last_error(),
           buf.raw[:2].hex()))
        k32.CloseHandle(h)
        break
    finish(out)


def finish(out):
    text = "\n".join(out) + "\n"
    open(os.path.join(HERE, "h_access.txt"), "w", encoding="utf-8").write(text)
    sys.stdout.write(text)


main()
