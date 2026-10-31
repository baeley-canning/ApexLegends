"""diag4.py -- the target's address space looks empty.  Is it?

diag3.txt facts:
  * control: QUERY_LIMITED handle -> rpm err=5 (so "no VM_READ" is 5, not 87)
  * control: VM_READ handle      -> rpm returns real bytes
  * target protection          -> raw=0x0 (not a protected process)
  * target: OpenProcess OK, but the VQE walk collected 0 MEM_IMAGE regions
    and every rpm returned 87.

87 is ERROR_INVALID_PARAMETER, which ReadProcessMemory produces for a handle
that is not usable as a process handle, or for an address/size the kernel
rejects.  So the questions are:
  1. does the walk actually reach real regions (count calls + first failure)?
  2. does rpm succeed at *any* address in the target?
  3. what NTSTATUS does NtReadVirtualMemory return (finer than Win32 error)?
  4. which anti-cheat driver is loaded, i.e. who could be stripping rights?

Output: temp/diag4.txt
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = "r5apex_dx12.exe"
REPORT = os.path.join(HERE, "diag4.txt")

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
ntdll.NtReadVirtualMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                      ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
ntdll.NtReadVirtualMemory.restype = ctypes.c_long


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
k32.IsWow64Process2.argtypes = [wt.HANDLE, ctypes.POINTER(wt.USHORT),
                                 ctypes.POINTER(wt.USHORT)]
k32.IsWow64Process2.restype = wt.BOOL


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
    return (buf.raw[:got.value] if ok else None), ctypes.get_last_error()


def ntrpm(h, addr, n=16):
    """Same read through ntdll: the NTSTATUS is more specific than Win32's 87."""
    buf = ctypes.create_string_buffer(n)
    got = ctypes.c_size_t(0)
    st = ntdll.NtReadVirtualMemory(h, ctypes.c_void_p(addr), buf, n,
                                   ctypes.byref(got))
    return (buf.raw[:got.value] if st == 0 else None), st & 0xFFFFFFFF, got.value


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


def arch(pid):
    """IsWow64Process2: 0x14c = i386, 0x8664 = amd64.  A 32-bit target would
    explain both the missing image regions and the failure above 4 GiB."""
    h = k32.OpenProcess(0x1000, False, pid)
    if not h:
        return "no handle (err=%d)" % ctypes.get_last_error()
    pm = wt.USHORT(0)
    nm = wt.USHORT(0)
    ok = k32.IsWow64Process2(h, ctypes.byref(pm), ctypes.byref(nm))
    err = ctypes.get_last_error()
    k32.CloseHandle(h)
    if not ok:
        return "IsWow64Process2 failed err=%d" % err
    names = {0x14C: "i386", 0x8664: "amd64", 0xAA64: "arm64", 0: "native"}
    return "process=%#x(%s) native=%#x(%s)" % (
        pm.value, names.get(pm.value, "?"), nm.value, names.get(nm.value, "?"))


def walk(h, budget=6000):
    """Return (regions, calls, stop_addr, last_err)."""
    addr, regions, calls, err = 0, [], 0, 0
    while calls < budget:
        mbi, err = vqe(h, addr)
        if not mbi:
            return regions, calls, addr, err
        calls += 1
        regions.append((mbi.BaseAddress, mbi.RegionSize, mbi.State, mbi.Type,
                        mbi.Protect))
        nxt = mbi.BaseAddress + mbi.RegionSize
        if nxt <= addr:
            break
        addr = nxt
    return regions, calls, addr, err



class ENUM_SERVICE_STATUSW(ctypes.Structure):
    _fields_ = [("name", ctypes.c_void_p), ("disp", ctypes.c_void_p),
                ("svcType", wt.DWORD), ("curState", wt.DWORD),
                ("ctrl", wt.DWORD), ("win32Exit", wt.DWORD),
                ("svcSpecific", wt.DWORD), ("checkPoint", wt.DWORD),
                ("waitHint", wt.DWORD)]


def drivers():
    """Which services/drivers are present, i.e. who could strip our rights."""
    adv = ctypes.WinDLL("advapi32", use_last_error=True)
    adv.OpenSCManagerW.restype = wt.HANDLE
    adv.OpenSCManagerW.argtypes = [wt.LPCWSTR, wt.LPCWSTR, wt.DWORD]
    adv.CloseServiceHandle.argtypes = [wt.HANDLE]
    adv.EnumServicesStatusW.argtypes = [wt.HANDLE, wt.DWORD, wt.DWORD,
                                        ctypes.c_void_p, wt.DWORD,
                                        ctypes.POINTER(wt.DWORD),
                                        ctypes.POINTER(wt.DWORD),
                                        ctypes.POINTER(wt.DWORD)]
    adv.EnumServicesStatusW.restype = wt.BOOL
    scm = adv.OpenSCManagerW(None, None, 0x0004)
    if not scm:
        return ["OpenSCManagerW failed err=%d" % ctypes.get_last_error()]
    need, cnt, resume = wt.DWORD(0), wt.DWORD(0), wt.DWORD(0)
    adv.EnumServicesStatusW(scm, 0x2, 0x2, None, 0, ctypes.byref(need),
                            ctypes.byref(cnt), ctypes.byref(resume))
    buf = ctypes.create_string_buffer(max(need.value, 0x10000))
    ok = adv.EnumServicesStatusW(scm, 0x2, 0x2, buf, ctypes.sizeof(buf),
                                 ctypes.byref(need), ctypes.byref(cnt),
                                 ctypes.byref(resume))
    lines = ["driver enumeration ok=%d count=%d" % (bool(ok), cnt.value)]
    if ok:
        blob = bytes(buf)
        step = ctypes.sizeof(ENUM_SERVICE_STATUSW)
        keys = ("easyanti", "eac", "battleye", "bedaisy", "vgk", "vgc",
                "anticheat", "faceit", "mhyprot")
        for i in range(cnt.value):
            e = ENUM_SERVICE_STATUSW.from_buffer_copy(blob[i * step:(i + 1) * step])
            nm = ctypes.wstring_at(e.name) if e.name else "?"
            low = nm.lower()
            if e.curState == 4 or any(k in low for k in keys):
                lines.append("   %-42s state=%d" % (nm, e.curState))
    adv.CloseServiceHandle(scm)
    return lines


def main():
    p("# diag4  64-bit=%s pid=%d" % (struct.calcsize("P") == 8, os.getpid()))

    p("")
    p("## control walk on our own process")
    h = k32.OpenProcess(0x0410, False, os.getpid())
    regs, calls, stop, err = walk(h, budget=6000)
    p("   regions=%d calls=%d stop=%#x err=%d" % (len(regs), calls, stop, err))
    p("   MEM_IMAGE=%d MEM_MAPPED=%d MEM_PRIVATE=%d"
      % (len([r for r in regs if r[3] == 0x1000000]),
         len([r for r in regs if r[3] == 0x40000]),
         len([r for r in regs if r[3] == 0x20000])))
    k32.CloseHandle(h)

    for pid in pids_named(EXE):
        p("")
        p("## target pid=%d  arch: %s" % (pid, arch(pid)))
        h = k32.OpenProcess(0x0410, False, pid)
        p("   OpenProcess h=%s err=%d"
          % (hex(h) if h else "0", ctypes.get_last_error()))
        if not h:
            continue
        regs, calls, stop, err = walk(h)
        p("   walk: regions=%d calls=%d stop=%#x last_err=%d"
          % (len(regs), calls, stop, err))
        p("   MEM_IMAGE=%d MEM_MAPPED=%d MEM_PRIVATE=%d committed=%d"
          % (len([r for r in regs if r[3] == 0x1000000]),
             len([r for r in regs if r[3] == 0x40000]),
             len([r for r in regs if r[3] == 0x20000]),
             len([r for r in regs if r[2] == 0x1000])))
        for r in regs[:12]:
            p("      base=%#012x size=%#010x state=%#06x type=%#08x prot=%#x" % r)

        com = [r for r in regs if r[2] == 0x1000]
        p("   rpm at the base of the first %d committed regions:" % min(len(com), 40))
        okc = 0
        for b, s, _st, _ty, _pr in com[:40]:
            raw, err = rpm(h, b)
            okc += 1 if raw else 0
            p("      %#012x %-26s err=%d"
              % (b, raw[:8].hex(" ") if raw else "FAIL", err))
        p("   rpm successes: %d/%d" % (okc, min(len(com), 40)))

        p("   ntdll.NtReadVirtualMemory probes:")
        for addr in (0x140000000, 0x7FFE0000, 0x10000):
            raw, st, got = ntrpm(h, addr)
            p("      %#012x -> status=%#x got=%d %s"
              % (addr, st, got, raw[:8].hex(" ") if raw else ""))
        k32.CloseHandle(h)

    p("")
    p("## drivers / services worth knowing about")
    for line in drivers():
        p("   " + line)

    with open(REPORT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")


main()
