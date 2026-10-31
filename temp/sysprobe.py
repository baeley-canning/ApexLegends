"""sysprobe.py -- same OpenProcess/read test, executed as LOCAL SYSTEM.

Hypothesis under test: EAC's Ob callback strips VM_READ only for interactive
user callers.  If a SYSTEM process is granted 0x10, this whole problem is solved
by running the tool as SYSTEM (schtasks /ru SYSTEM), no driver needed.

Writes temp/sysprobe.txt.
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import namehunt as nh
import readprobe2 as rp2

REPORT = os.path.join(HERE, "sysprobe.txt")
out = []


def p(s=""):
    out.append(s)


def whoami():
    k32 = ctypes.windll.kernel32
    adv = ctypes.windll.advapi32
    adv.OpenProcessToken.argtypes = [wt.HANDLE, wt.DWORD, ctypes.POINTER(wt.HANDLE)]
    adv.OpenProcessToken.restype = wt.BOOL
    k32.GetCurrentProcess.restype = wt.HANDLE
    adv.GetTokenInformation.argtypes = [wt.HANDLE, ctypes.c_int, ctypes.c_void_p,
                                        wt.DWORD, ctypes.POINTER(wt.DWORD)]
    adv.GetTokenInformation.restype = wt.BOOL
    k32.OpenProcessToken.argtypes = [wt.HANDLE, wt.DWORD, ctypes.POINTER(wt.HANDLE)]
    h = wt.HANDLE()
    if not k32.OpenProcessToken(k32.GetCurrentProcess(), 0x8, ctypes.byref(h)):
        return "token err=%d" % ctypes.get_last_error()
    n = wt.DWORD(0)
    adv.GetTokenInformation(h, 1, None, 0, ctypes.byref(n))       # TokenUser
    buf = ctypes.create_string_buffer(max(n.value, 8))
    if not adv.GetTokenInformation(h, 1, buf, n, ctypes.byref(n)):
        return "user-info err=%d" % ctypes.get_last_error()
    # TOKEN_USER: SID_AND_ATTRIBUTES{ PSID Sid; DWORD Attributes; }
    psid = ctypes.c_void_p.from_buffer(buf).value
    adv.ConvertSidToStringSidW.argtypes = [ctypes.c_void_p, ctypes.POINTER(wt.LPWSTR)]
    s = wt.LPWSTR()
    if adv.ConvertSidToStringSidW(psid, ctypes.byref(s)):
        return s.value
    return "sid ?"


def main():
    p("identity: %s  elevated=%s  pid=%d"
      % (whoami(), bool(ctypes.windll.shell32.IsUserAnAdmin()), os.getpid()))
    pid = nh.find_pid(nh.EXE)
    p("target: %s pid=%s" % (nh.EXE, pid))
    if not pid:
        return 1
    ex_ssn, _ = nh.disk_export(
        os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                     "System32", "ntdll.dll"), "NtReadVirtualMemoryEx")
    plain_ssn, _ = nh.disk_export(
        os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                     "System32", "ntdll.dll"), "NtReadVirtualMemory")
    sysc = nh.Syscall()
    for acc in (0x1FFFFF, 0x1410, 0x1000, 0x410):
        h = nh.k32.OpenProcess(acc, False, pid)
        if not h:
            p("mask %#08x -> NULL err=%d" % (acc, ctypes.get_last_error()))
            continue
        p("mask %#08x -> %#x" % (acc, h))
        got = ctypes.c_size_t(0)
        buf = ctypes.create_string_buffer(2)
        rpm = nh.k32.ReadProcessMemory(h, ctypes.c_void_p(rp2.PROBE), buf, 2,
                                       ctypes.byref(got))
        p("   rpm=%d err=%d bytes=%r" % (bool(rpm), ctypes.get_last_error(),
                                         buf.raw[:got.value]))
        for ssn, tag in ((plain_ssn, "plain"), (ex_ssn, "ex")):
            got = ctypes.c_size_t(0)
            b = ctypes.create_string_buffer(2)
            st = sysc.stub(ssn)(h, ctypes.c_void_p(rp2.PROBE), b, 2,
                                ctypes.byref(got), 0)
            p("   %-5s status=%#010x got=%d bytes=%r"
              % (tag, st & 0xFFFFFFFF, got.value, b.raw[:got.value]))
        nh.k32.CloseHandle(h)

    # what rights did we actually get?
    me = os.getpid()
    h = nh.k32.OpenProcess(0x1FFFFF, False, pid)
    hs = rp2.handles()
    for owner, hv, granted, tidx in hs:
        if owner == me and hv == h:
            p("granted=%#x vm_read=%s type=%d" % (granted,
                                                   bool(granted & 0x10), tidx))
            break
    else:
        p("own handle not found in table (%d entries)" % len(hs))
    if h:
        nh.k32.CloseHandle(h)
    return 0


if __name__ == "__main__":
    rc = main()
    with open(REPORT, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    sys.exit(rc)
