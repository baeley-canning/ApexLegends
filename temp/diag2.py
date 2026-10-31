"""diag2.py -- why does ReadProcessMemory return nothing at all?

mods.txt (elevated): OpenProcess(QUERY_INFO|VM_READ) succeeded, yet RPM failed
at the PEB, at 0x140000000 and inside every region, and VirtualQueryEx walked
zero MEM_IMAGE regions.  When *every* call fails the fault is usually in the
ctypes plumbing or in the handle, not in the target.

This file is the control experiment: the exact same API calls run twice, once
against r5apex_dx12.exe and once against this very process (which obviously has
readable memory).  Same code, same prototypes -> any difference is the target,
and the per-call GetLastError says which flavour of refusal it is
(5 = access denied, 87 = handle lacks VM_READ, 299 = partial copy).

Output: temp/diag2.txt
"""
import ctypes
import ctypes.wintypes as wt
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = "r5apex_dx12.exe"
REPORT = os.path.join(HERE, "diag2.txt")

k32 = ctypes.WinDLL("kernel32", use_last_error=True)

# Declare the whole family up front.  The earlier scripts called OpenProcess /
# CreateToolhelp32Snapshot without prototypes, so ctypes' default c_int restype
# truncated the 64-bit HANDLE -- which is enough on its own to explain "handle
# opens fine, every read fails".
k32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
k32.OpenProcess.restype = wt.HANDLE
k32.CloseHandle.argtypes = [wt.HANDLE]
k32.CloseHandle.restype = wt.BOOL
k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                   ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
k32.ReadProcessMemory.restype = wt.BOOL
k32.CreateToolhelp32Snapshot.argtypes = [wt.DWORD, wt.DWORD]
k32.CreateToolhelp32Snapshot.restype = wt.HANDLE
k32.Process32FirstW.argtypes = [wt.HANDLE, ctypes.c_void_p]
k32.Process32NextW.argtypes = [wt.HANDLE, ctypes.c_void_p]
k32.GetCurrentProcess.restype = wt.HANDLE


class MBI(ctypes.Structure):
    _fields_ = [("BaseAddress", ctypes.c_ulonglong),
                ("AllocationBase", ctypes.c_ulonglong),
                ("AllocationProtect", wt.DWORD), ("__a1", wt.DWORD),
                ("RegionSize", ctypes.c_ulonglong),
                ("State", wt.DWORD), ("Protect", wt.DWORD),
                ("Type", wt.DWORD), ("__a2", wt.DWORD)]


k32.VirtualQueryEx.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.POINTER(MBI),
                                ctypes.c_size_t]
k32.VirtualQueryEx.restype = ctypes.c_size_t


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD),
                ("th32ProcessID", wt.DWORD),
                ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
                ("th32ModuleID", wt.DWORD), ("cntThreads", wt.DWORD),
                ("th32ParentProcessID", wt.DWORD), ("pcPriClassBase", ctypes.c_long),
                ("dwFlags", wt.DWORD), ("szExeFile", wt.WCHAR * 260)]


MASKS = [(0x1F0FFF, "ALL_ACCESS"), (0x0410, "QUERY_INFO|VM_READ"),
         (0x0010, "VM_READ"), (0x0400, "QUERY_INFORMATION"),
         (0x1000, "QUERY_LIMITED")]

out = []


def p(s=""):
    print(s)
    out.append(s)


def find_pids(exe):
    snap = k32.CreateToolhelp32Snapshot(0x2, 0)
    pe = PROCESSENTRY32W()
    pe.dwSize = ctypes.sizeof(pe)
    pids = []
    try:
        ok = k32.Process32FirstW(snap, ctypes.byref(pe))
        while ok:
            if pe.szExeFile.lower() == exe.lower():
                pids.append((pe.th32ProcessID, pe.cntThreads))
            ok = k32.Process32NextW(snap, ctypes.byref(pe))
    finally:
        k32.CloseHandle(snap)
    return pids


def rpm(h, addr, n):
    buf = ctypes.create_string_buffer(n)
    got = ctypes.c_size_t(0)
    ok = k32.ReadProcessMemory(h, ctypes.c_void_p(addr), buf, n, ctypes.byref(got))
    if not ok:
        return None, ctypes.get_last_error(), got.value
    return buf.raw[:got.value], 0, got.value


def vqe(h, addr):
    mbi = MBI()
    n = k32.VirtualQueryEx(h, ctypes.c_void_p(addr), ctypes.byref(mbi),
                            ctypes.sizeof(mbi))
    return (mbi, 0) if n else (None, ctypes.get_last_error())


def image_regions(h, budget=3000):
    addr, found, calls, err = 0, [], 0, 0
    while addr < 0x7FFFFFFF0000 and calls < budget:
        mbi, err = vqe(h, addr)
        if not mbi:
            break
        calls += 1
        if mbi.Type == 0x1000000:
            found.append((mbi.BaseAddress, mbi.RegionSize, mbi.State))
        nxt = mbi.BaseAddress + mbi.RegionSize
        if nxt <= addr:
            break
        addr = nxt
    return found, addr, err, calls


def report_target(label, h):
    p("")
    p("## %s  handle=%#x" % (label, h or 0))
    if not h:
        p("   OpenProcess failed, err=%d" % ctypes.get_last_error())
        return
    raw, err, got = rpm(h, 0x140000000, 0x40)
    p("   rpm(0x140000000,0x40) -> %s err=%d got=%d"
      % (raw[:16].hex(" ") if raw else "FAIL", err, got))
    mbi, verr = vqe(h, 0)
    p("   vqe(0) -> %s err=%d"
      % (("base=%#x size=%#x type=%#x state=%#x"
          % (mbi.BaseAddress, mbi.RegionSize, mbi.Type, mbi.State))
         if mbi else "FAIL", verr))
    regions, stop, err, calls = image_regions(h, budget=400)
    p("   vqe walk: %d calls -> %d MEM_IMAGE regions, stop=%#x err=%d"
      % (calls, len(regions), stop, err))
    for b, s, st in regions[:8]:
        p("      image base=%#012x size=%#010x state=%#x" % (b, s, st))



def main():
    p("# diag2 -- API/handle problem, or target problem?")
    p("# own pid=%d  GetCurrentProcess=%#x" % (os.getpid(), k32.GetCurrentProcess()))

    report_target("CONTROL: own process, GetCurrentProcess()",
                  k32.GetCurrentProcess())
    h_self = k32.OpenProcess(0x0410, False, os.getpid())
    report_target("CONTROL: own process, OpenProcess(QUERY_INFO|VM_READ)", h_self)
    if h_self:
        k32.CloseHandle(h_self)

    pids = find_pids(EXE)
    p("")
    p("## %s instances (pid, threads): %s" % (EXE, pids if pids else "none"))
    for pid, threads in pids:
        p("")
        p("## target pid=%d threads=%d" % (pid, threads))
        for mask, name in MASKS:
            h = k32.OpenProcess(mask, False, pid)
            err = ctypes.get_last_error()
            p("   OpenProcess(%#06x %-21s) h=%s err=%d"
              % (mask, name, hex(h) if h else "0", err))
            if not h:
                continue
            raw, rerr, got = rpm(h, 0x140000000, 0x40)
            mbi, verr = vqe(h, 0)
            p("      rpm(0x140000000) -> %s err=%d got=%d"
              % (raw[:16].hex(" ") if raw else "FAIL", rerr, got))
            p("      vqe(0) -> %s err=%d"
              % (("size=%#x type=%#x" % (mbi.RegionSize, mbi.Type))
                 if mbi else "FAIL", verr))
            k32.CloseHandle(h)
            if raw:
                break

    with open(REPORT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")


main()
