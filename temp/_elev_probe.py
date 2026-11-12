r"""temp\_trig_run.ps1 -- why does dumplive.run_elevated get err=5 while
PowerShell's -Verb RunAs works?  Same ShellExecuteExW, different arguments.
Each variant launches a trivial elevated python that exits at once.
Read temp\_elev_probe.txt.
RESULT (08/11): the shipped SHELLEXECUTEINFOW was 104 bytes (lpFile field absent) so
cbSize was rejected; 112 bytes -- the correct layout -- works with the shipped flags.
"""
import ctypes
import ctypes.wintypes as wt
import os
import sys

shell32 = ctypes.WinDLL("shell32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
HERE = r"c:\Users\New User\OneDrive\Desktop\cheating\ext"
PY = sys.executable
OUT = r"c:\Users\New User\OneDrive\Desktop\cheating\temp\_elev_probe.txt"
lines = []


class SEI(ctypes.Structure):
    _fields_ = [("cbSize", wt.DWORD), ("fMask", wt.ULONG), ("hwnd", wt.HWND),
                ("lpVerb", wt.LPCWSTR), ("lpFile", wt.LPCWSTR),
                ("lpParameters", wt.LPCWSTR), ("lpDirectory", wt.LPCWSTR),
                ("nShow", ctypes.c_int), ("hInstApp", wt.HINSTANCE),
                ("lpIDList", ctypes.c_void_p), ("lpClass", wt.LPCWSTR),
                ("hkeyClass", wt.HKEY),
                ("dwHotKey", wt.DWORD), ("hIcon", wt.HANDLE), ("hProcess", wt.HANDLE)]


def say(s):
    lines.append(s)
    print(s, flush=True)


def attempt(name, **kw):
    ctypes.set_last_error(0)
    sei = SEI()
    sei.cbSize = ctypes.sizeof(sei)
    sei.fMask = kw.pop("fMask", 0x40)
    sei.hwnd = None
    sei.lpVerb = "runas"
    sei.lpFile = kw.pop("lpFile", PY)
    sei.lpParameters = kw.pop("lpParameters", "-c pass")
    sei.lpDirectory = kw.pop("lpDirectory", HERE)
    sei.nShow = kw.pop("nShow", 1)
    ok = shell32.ShellExecuteExW(ctypes.byref(sei))
    err = ctypes.get_last_error()
    say("%-34s ok=%s err=%d sizeof=%d cbSize_used=%d hProcess=%s"
        % (name, bool(ok), err, ctypes.sizeof(sei), sei.cbSize, sei.hProcess))
    if ok and sei.hProcess:
        kernel32.WaitForSingleObject(sei.hProcess, 30000)
        code = wt.DWORD(0)
        kernel32.GetExitCodeProcess(sei.hProcess, ctypes.byref(code))
        say("%-34s child exit=%d" % (name, code.value))
        kernel32.CloseHandle(sei.hProcess)
    return bool(ok)


attempt("baseline 112 (as shipped)")
attempt("fMask |= NOASYNC 0x100", fMask=0x141)
attempt("lpDirectory=None", lpDirectory=None)
attempt("nShow=1, no directory, no noclose", fMask=0x0, lpDirectory=None)
attempt("lpFile=cmd.exe runas", lpFile=r"C:\Windows\System32\cmd.exe",
        lpParameters="/c exit")
attempt("baseline again", )

say("")
say("VERDICT: %s hypotheses probed" % len(lines))
with open(OUT, "w") as f:
    f.write("\n".join(lines) + "\n")
