"""diag3.py -- what exactly is refused, and by whom?

diag2.txt facts:
  * VQE works on the target (MEM_FREE at address 0, err=0).
  * RPM fails on the target for ALL_ACCESS, QUERY_INFO|VM_READ, VM_READ,
    QUERY_INFORMATION and QUERY_LIMITED handles -- always err=87.
  * RPM on our *own* process returns 299 at 0x140000000, the healthy answer
    for an unmapped address: the plumbing works.

So err 87 is what needs decoding.  Two candidates:
  (a) 87 == "this handle has no PROCESS_VM_READ" -- provable by opening a
      normal process with QUERY_LIMITED only and trying to read it;
  (b) 87 == "granted access was stripped by an ObRegisterCallbacks driver",
      which is what EAC does: OpenProcess succeeds, the requested rights are
      silently dropped, and ProcessProtectionInformation is the tell.

This script runs (a) as a control and dumps the protection facts for (b).
Output: temp/diag3.txt
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = "r5apex_dx12.exe"
REPORT = os.path.join(HERE, "diag3.txt")

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
ntdll = ctypes.WinDLL("ntdll")

k32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
k32.OpenProcess.restype = wt.HANDLE
k32.CloseHandle.argtypes = [wt.HANDLE]
k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                   ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
k32.ReadProcessMemory.restype = wt.BOOL
k32.CreateToolhelp32Snapshot.argtypes = [wt.DWORD, wt.DWORD]
k32.CreateToolhelp32Snapshot.restype = wt.HANDLE
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


out = []


def p(s=""):
    print(s)
    out.append(s)


def rpm(h, addr, n=16):
    buf = ctypes.create_string_buffer(n)
    got = ctypes.c_size_t(0)
    ok = k32.ReadProcessMemory(h, ctypes.c_void_p(addr), buf, n, ctypes.byref(got))
    return (buf.raw[:got.value] if ok else None), ctypes.get_last_error(), got.value


def vqe(h, addr):
    mbi = MBI()
    n = k32.VirtualQueryEx(h, ctypes.c_void_p(addr), ctypes.byref(mbi),
                            ctypes.sizeof(mbi))
    return (mbi if n else None), ctypes.get_last_error()


def pids_named(exe):
    snap = k32.CreateToolhelp32Snapshot(0x2, 0)
    pe = PROCESSENTRY32W()
    pe.dwSize = ctypes.sizeof(pe)
    found = []
    try:
        ok = k32.Process32FirstW(snap, ctypes.byref(pe))
        while ok:
            if pe.szExeFile.lower() == exe.lower():
                found.append(pe.th32ProcessID)
            ok = k32.Process32NextW(snap, ctypes.byref(pe))
    finally:
        k32.CloseHandle(snap)
    return found


def image_regions(h, budget=4000):
    addr, found = 0, []
    for _ in range(budget):
        mbi, _err = vqe(h, addr)
        if not mbi:
            break
        if mbi.Type == 0x1000000:
            found.append((mbi.BaseAddress, mbi.RegionSize))
        nxt = mbi.BaseAddress + mbi.RegionSize
        if nxt <= addr:
            break
        addr = nxt
    return found



def protection(pid):
    """NtQueryInformationProcess(ProcessProtectionInformation = 61)."""
    h = k32.OpenProcess(0x1000, False, pid)
    if not h:
        return "no QUERY_LIMITED handle (err=%d)" % ctypes.get_last_error()
    val = wt.DWORD(0)
    ret = ctypes.c_ulong(0)
    st = ntdll.NtQueryInformationProcess(h, 61, ctypes.byref(val),
                                         ctypes.sizeof(val), ctypes.byref(ret))
    k32.CloseHandle(h)
    if st != 0:
        return "status=%#x" % st
    lvl = val.value
    kind = lvl & 0x7
    signer = (lvl >> 4) & 0xFFF
    names = {0: "none", 1: "light", 2: "protected", 3: "max"}
    return "raw=%#x type=%s signer=%#x" % (lvl, names.get(kind, "?"), signer)


def main():
    p("# diag3  interpreter is 64-bit: %s" % (struct.calcsize("P") == 8))
    p("# pid=%d  hproc=%#x" % (os.getpid(), k32.GetCurrentProcess()))
    have = []

    p("")
    p("## control A: own process, QUERY_LIMITED handle, rpm at a mapped page")
    h = k32.OpenProcess(0x1000, False, os.getpid())
    have = [b for b, s in image_regions(h) if s > 0x100000]
    p("   own image regions >1MB: %d%s"
      % (len(have), (" first=%#x" % have[0]) if have else ""))
    if have:
        raw, err, got = rpm(h, have[0])
        p("   rpm(%#x) QUERY_LIMITED -> %s err=%d"
          % (have[0], raw.hex(" ") if raw else "FAIL", err))
    k32.CloseHandle(h)

    p("")
    p("## control B: own process, VM_READ handle, same page")
    h = k32.OpenProcess(0x10, False, os.getpid())
    if have:
        raw, err, got = rpm(h, have[0])
        p("   rpm(%#x) VM_READ -> %s err=%d"
          % (have[0], raw.hex(" ") if raw else "FAIL", err))
    k32.CloseHandle(h)
    p("   => 87 in A + bytes in B means err 87 == 'handle has no VM_READ'.")

    for pid in pids_named(EXE):
        p("")
        p("## target %s pid=%d" % (EXE, pid))
        p("   protection: %s" % protection(pid))
        h = k32.OpenProcess(0x0410, False, pid)
        p("   OpenProcess(QUERY_INFO|VM_READ) h=%s err=%d"
          % (hex(h) if h else "0", ctypes.get_last_error()))
        if not h:
            continue
        regs = image_regions(h)
        p("   MEM_IMAGE regions visible through the handle: %d" % len(regs))
        for b, s in sorted(regs, key=lambda x: -x[1])[:6]:
            raw, err, got = rpm(h, b)
            p("      base=%#012x size=%#010x rpm -> %s err=%d"
              % (b, s, (raw[:8].hex(" ") if raw else "FAIL"), err))
        k32.CloseHandle(h)

    with open(REPORT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")


main()
