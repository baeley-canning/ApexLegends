"""diag5.py -- ReadProcessMemory is refused by the target (NTSTATUS 0xC000000D).

Established so far (diag3/diag4):
  control, own process, handle WITHOUT VM_READ  -> rpm err=5   (ACCESS_DENIED)
  control, own process, handle WITH VM_READ     -> rpm works
  target, handle WITH VM_READ                   -> every rpm fails, NTSTATUS
                                                   0xC000000D (INVALID_PARAMETER)
  target VAD walk through the same handle       -> works, 5702 committed regions
                                                   (so QUERY_INFORMATION is intact)

0xC000000D is *not* what a stripped handle produces (that is 0xC0000005 -> 5),
so the refusal happens inside the read path, i.e. something filter-level.
This script asks, in order:
  1. is EAC present (service, driver, processes, module in the target)?
  2. does NtWriteVirtualMemory get the same treatment (read vs write)?
  3. does an ALL_ACCESS handle, or a duplicated handle, change anything?
  4. does any other read primitive still work?
     NtWow64ReadVirtualMemory64, rpm on a thread stack, GetThreadContext,
     QueryFullProcessImageName, toolhelp modules
  5. what are the target's MEM_IMAGE regions (module base without VM_READ)?

Output: temp/diag5.txt
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = "r5apex_dx12.exe"
CONTROL_EXE = "explorer.exe"
REPORT = os.path.join(HERE, "diag5.txt")

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
ntdll = ctypes.WinDLL("ntdll")
adv = ctypes.WinDLL("advapi32", use_last_error=True)

k32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
k32.OpenProcess.restype = wt.HANDLE
k32.CloseHandle.argtypes = [wt.HANDLE]
k32.CloseHandle.restype = wt.BOOL
k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                   ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
k32.ReadProcessMemory.restype = wt.BOOL
k32.WriteProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                    ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
k32.WriteProcessMemory.restype = wt.BOOL
k32.CreateToolhelp32Snapshot.argtypes = [wt.DWORD, wt.DWORD]
k32.CreateToolhelp32Snapshot.restype = wt.HANDLE
k32.Process32FirstW.argtypes = [wt.HANDLE, ctypes.c_void_p]
k32.Process32NextW.argtypes = [wt.HANDLE, ctypes.c_void_p]
k32.Module32FirstW.argtypes = [wt.HANDLE, ctypes.c_void_p]
k32.Module32NextW.argtypes = [wt.HANDLE, ctypes.c_void_p]
k32.OpenThread.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
k32.OpenThread.restype = wt.HANDLE
k32.DuplicateHandle.argtypes = [wt.HANDLE, wt.HANDLE, wt.HANDLE,
                                ctypes.POINTER(wt.HANDLE), wt.DWORD, wt.BOOL,
                                wt.DWORD]
k32.DuplicateHandle.restype = wt.BOOL
k32.QueryFullProcessImageNameW.argtypes = [wt.HANDLE, wt.DWORD, ctypes.c_void_p,
                                           ctypes.POINTER(wt.DWORD)]
k32.QueryFullProcessImageNameW.restype = wt.BOOL
k32.GetCurrentProcess.restype = wt.HANDLE
k32.GetThreadContext.argtypes = [wt.HANDLE, ctypes.c_void_p]
k32.GetThreadContext.restype = wt.BOOL
k32.Thread32First.argtypes = [wt.HANDLE, ctypes.c_void_p]
k32.Thread32Next.argtypes = [wt.HANDLE, ctypes.c_void_p]

ntdll.NtReadVirtualMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                      ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
ntdll.NtReadVirtualMemory.restype = ctypes.c_long
ntdll.NtWriteVirtualMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                       ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
ntdll.NtWriteVirtualMemory.restype = ctypes.c_long
# NtWow64ReadVirtualMemory64 is gone on recent Windows builds; keep it optional.
try:
    ntdll.NtWow64ReadVirtualMemory64.argtypes = [wt.HANDLE, ctypes.c_ulonglong,
                                                 ctypes.c_void_p, ctypes.c_ulonglong,
                                                 ctypes.POINTER(ctypes.c_ulonglong)]
    ntdll.NtWow64ReadVirtualMemory64.restype = ctypes.c_long
    HAVE_WOW64_READ = True
except AttributeError:
    HAVE_WOW64_READ = False
try:
    ntdll.NtReadVirtualMemoryEx.argtypes = [wt.HANDLE, ctypes.c_void_p,
                                             ctypes.c_void_p, ctypes.c_size_t,
                                             ctypes.POINTER(ctypes.c_size_t),
                                             wt.ULONG]
    ntdll.NtReadVirtualMemoryEx.restype = ctypes.c_long
    HAVE_READ_EX = True
except AttributeError:
    HAVE_READ_EX = False



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


class MODULEENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("th32ModuleID", wt.DWORD),
                ("th32ProcessID", wt.DWORD), ("GlblcntUsage", wt.DWORD),
                ("ProccntUsage", wt.DWORD), ("modBaseAddr", ctypes.c_void_p),
                ("modBaseSize", wt.DWORD), ("hModule", wt.HMODULE),
                ("szModule", wt.WCHAR * 256), ("szExePath", wt.WCHAR * 260)]


class CONTEXT64(ctypes.Structure):
    """Leading part of the amd64 CONTEXT record (full size is 0x4D0)."""
    _fields_ = [("P1Home", ctypes.c_ulonglong), ("P2Home", ctypes.c_ulonglong),
                ("P3Home", ctypes.c_ulonglong), ("P4Home", ctypes.c_ulonglong),
                ("P5Home", ctypes.c_ulonglong), ("P6Home", ctypes.c_ulonglong),
                ("ContextFlags", wt.DWORD), ("MxCsr", wt.DWORD),
                ("SegCs", wt.WORD), ("SegDs", wt.WORD), ("SegEs", wt.WORD),
                ("SegFs", wt.WORD), ("SegGs", wt.WORD), ("SegSs", wt.WORD),
                ("EFlags", wt.DWORD),
                ("Dr0", ctypes.c_ulonglong), ("Dr1", ctypes.c_ulonglong),
                ("Dr2", ctypes.c_ulonglong), ("Dr3", ctypes.c_ulonglong),
                ("Dr6", ctypes.c_ulonglong), ("Dr7", ctypes.c_ulonglong),
                ("Rax", ctypes.c_ulonglong), ("Rcx", ctypes.c_ulonglong),
                ("Rdx", ctypes.c_ulonglong), ("Rbx", ctypes.c_ulonglong),
                ("Rsp", ctypes.c_ulonglong), ("Rbp", ctypes.c_ulonglong),
                ("Rsi", ctypes.c_ulonglong), ("Rdi", ctypes.c_ulonglong),
                ("R8", ctypes.c_ulonglong), ("R9", ctypes.c_ulonglong),
                ("R10", ctypes.c_ulonglong), ("R11", ctypes.c_ulonglong),
                ("R12", ctypes.c_ulonglong), ("R13", ctypes.c_ulonglong),
                ("R14", ctypes.c_ulonglong), ("R15", ctypes.c_ulonglong),
                ("Rip", ctypes.c_ulonglong)]


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
    buf = ctypes.create_string_buffer(n)
    got = ctypes.c_size_t(0)
    st = ntdll.NtReadVirtualMemory(h, ctypes.c_void_p(addr), buf, n,
                                   ctypes.byref(got))
    return (buf.raw[:got.value] if st == 0 else None), st & 0xFFFFFFFF


def ntwpm(h, addr):
    buf = ctypes.create_string_buffer(8)
    got = ctypes.c_size_t(0)
    st = ntdll.NtWriteVirtualMemory(h, ctypes.c_void_p(addr), buf, 8,
                                    ctypes.byref(got))
    return st & 0xFFFFFFFF


def vqe(h, addr):
    mbi = MBI()
    n = k32.VirtualQueryEx(h, ctypes.c_void_p(addr), ctypes.byref(mbi),
                            ctypes.sizeof(mbi))
    return (mbi if n else None), ctypes.get_last_error()


def pids_named(exe, want_all=False):
    snap = k32.CreateToolhelp32Snapshot(0x2, 0)
    pe = PROCESSENTRY32W()
    pe.dwSize = ctypes.sizeof(pe)
    found = []
    ok = k32.Process32FirstW(snap, ctypes.byref(pe))
    while ok:
        low = pe.szExeFile.lower()
        if (want_all and ("easy" in low or "eac" in low)) or low == exe.lower():
            found.append((pe.th32ProcessID, pe.szExeFile))
        ok = k32.Process32NextW(snap, ctypes.byref(pe))
    k32.CloseHandle(snap)
    return found


def image_regions(h, budget=400000):
    """Full VAD walk; a game process has far more than 6000 regions."""
    addr, res, calls, err = 0, [], 0, 0
    while calls < budget:
        mbi, err = vqe(h, addr)
        if not mbi:
            break
        calls += 1
        if mbi.Type == 0x1000000:  # MEM_IMAGE
            res.append((mbi.BaseAddress, mbi.RegionSize, mbi.Protect))
        nxt = mbi.BaseAddress + mbi.RegionSize
        if nxt <= addr:
            break
        addr = nxt
    return res, calls, addr, err


class SYSTEM_MODULE_ENTRY(ctypes.Structure):
    _fields_ = [("Reserved1", ctypes.c_void_p), ("Reserved2", ctypes.c_void_p),
                ("ImageBase", ctypes.c_void_p), ("ImageSize", wt.ULONG),
                ("Flags", wt.ULONG), ("LoadOrderIndex", wt.WORD),
                ("InitOrderIndex", wt.WORD), ("LoadCount", wt.WORD),
                ("ModuleNameOffset", wt.WORD), ("ImageName", ctypes.c_char * 256)]


class ENUM_SERVICE_STATUSW(ctypes.Structure):
    _fields_ = [("name", ctypes.c_void_p), ("disp", ctypes.c_void_p),
                ("svcType", wt.DWORD), ("curState", wt.DWORD),
                ("ctrl", wt.DWORD), ("win32Exit", wt.DWORD),
                ("svcSpecific", wt.DWORD), ("checkPoint", wt.DWORD),
                ("waitHint", wt.DWORD)]


def kernel_modules():
    """NtQuerySystemInformation(SystemModuleInformation) lists loaded drivers."""
    ntdll.NtQuerySystemInformation.restype = ctypes.c_long
    need = wt.ULONG(0)
    ntdll.NtQuerySystemInformation(11, None, 0, ctypes.byref(need))
    buf = ctypes.create_string_buffer(max(need.value, 0x10000))
    st = ntdll.NtQuerySystemInformation(11, buf, ctypes.sizeof(buf),
                                        ctypes.byref(need))
    if st != 0:
        return ["SystemModuleInformation status=%#x" % (st & 0xFFFFFFFF)]
    count = ctypes.cast(buf, ctypes.POINTER(wt.ULONG)).contents.value
    step = ctypes.sizeof(SYSTEM_MODULE_ENTRY)
    base = ctypes.addressof(buf) + 8
    lines = ["loaded kernel modules: %d" % count]
    for i in range(min(count, 400)):
        e = SYSTEM_MODULE_ENTRY.from_buffer_copy(
            ctypes.string_at(base + i * step, step))
        nm = e.ImageName.decode("latin-1").split("\\")[-1]
        if any(k in nm.lower() for k in ("easy", "eac", "be", "battle",
                                         "vgk", "vgc", "anticheat", "hpv")):
            lines.append("   %-24s base=%#x size=%#x"
                         % (nm, e.ImageBase or 0, e.ImageSize))
    return lines


def driver_services():
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
        return ["OpenSCManagerW err=%d" % ctypes.get_last_error()]
    need, cnt, resume = wt.DWORD(0), wt.DWORD(0), wt.DWORD(0)
    adv.EnumServicesStatusW(scm, 0x2, 0x3, None, 0, ctypes.byref(need),
                            ctypes.byref(cnt), ctypes.byref(resume))
    buf = ctypes.create_string_buffer(max(need.value, 0x20000))
    ok = adv.EnumServicesStatusW(scm, 0x2, 0x3, buf, ctypes.sizeof(buf),
                                 ctypes.byref(need), ctypes.byref(cnt),
                                 ctypes.byref(resume))
    lines = ["driver services enumerated=%d ok=%d" % (cnt.value, bool(ok))]
    if ok:
        blob = bytes(buf)
        step = ctypes.sizeof(ENUM_SERVICE_STATUSW)
        for i in range(cnt.value):
            e = ENUM_SERVICE_STATUSW.from_buffer_copy(blob[i * step:(i + 1) * step])
            nm = ctypes.wstring_at(e.name) if e.name else "?"
            if any(k in nm.lower() for k in ("easy", "eac", "battle", "be",
                                             "vgk", "vgc", "anticheat", "hpv")):
                lines.append("   %-40s state=%d" % (nm, e.curState))
    adv.CloseServiceHandle(scm)
    return lines


def game_modules(pid):
    """Toolhelp module list: PEB/Ldr walk internally, so it may also be refused."""
    snap = k32.CreateToolhelp32Snapshot(0x8 | 0x10, pid)  # SNAPMODULE|SNAPMODULE32
    if not snap or snap == -1:
        return None, "CreateToolhelp32Snapshot err=%d" % ctypes.get_last_error()
    me = MODULEENTRY32W()
    me.dwSize = ctypes.sizeof(me)
    mods = []
    ok = k32.Module32FirstW(snap, ctypes.byref(me))
    while ok:
        mods.append((me.szModule, me.modBaseAddr or 0, me.modBaseSize))
        ok = k32.Module32NextW(snap, ctypes.byref(me))
    k32.CloseHandle(snap)
    return mods, "ok"


MASKS = [("ALL_ACCESS", 0x1FFFFF), ("QUERY_INFO|VM_READ", 0x0410),
         ("VM_READ", 0x0010), ("QUERY_INFO", 0x0400),
         ("QUERY_LIMITED", 0x1000), ("VM_OPERATION", 0x0008),
         ("SYNCHRONIZE", 0x00100000)]


def main():
    p("# diag5  64-bit=%s pid=%d" % (struct.calcsize("P") == 8, os.getpid()))
    p("")
    p("## who could be refusing the read")
    for line in kernel_modules():
        p("   " + line)
    for line in driver_services():
        p("   " + line)
    eac = pids_named(EXE, want_all=True)
    p("   easyanticheat processes: %s"
      % (", ".join("%s(%d)" % (n, i) for i, n in eac if n.lower() != EXE) or "none"))
    targets = [i for i, n in eac if n.lower() == EXE]
    p("   %s pids: %s" % (EXE, targets or "not running"))

    for pid in targets:
        p("")
        p("## target pid=%d" % pid)

        p("   -- access mask vs. read status (16 bytes at 0x140000000)")
        for label, mask in MASKS:
            h = k32.OpenProcess(mask, False, pid)
            if not h:
                p("      %-20s OpenProcess err=%d" % (label, ctypes.get_last_error()))
                continue
            raw, st = ntrpm(h, 0x140000000)
            wr = ntwpm(h, 0x140000000)
            p("      %-20s NtRead=%#010x NtWrite=%#010x %s"
              % (label, st, wr, raw[:8].hex(" ") if raw else ""))
            k32.CloseHandle(h)

        h = k32.OpenProcess(0x1FFFFF, False, pid)
        if not h:
            p("   no ALL_ACCESS handle, stopping here")
            continue

        p("   -- duplicate handle, then read through the copy")
        cur = k32.GetCurrentProcess()
        dup = wt.HANDLE()
        ok = k32.DuplicateHandle(cur, h, cur, ctypes.byref(dup), 0, False, 0x2)
        p("      DuplicateHandle ok=%d err=%d" % (bool(ok), ctypes.get_last_error()))
        if ok:
            raw, st = ntrpm(dup, 0x140000000)
            p("      NtRead through duplicate=%#010x %s"
              % (st, raw[:8].hex(" ") if raw else ""))
            k32.CloseHandle(dup)

        p("   -- other primitives")
        buf = ctypes.create_string_buffer(260)
        n = wt.DWORD(260)
        ok = k32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(n))
        p("      QueryFullProcessImageNameW ok=%d err=%d path=%s"
          % (bool(ok), ctypes.get_last_error(),
             buf.value if ok else ""))
        got64 = ctypes.c_ulonglong(0)
        if HAVE_WOW64_READ:
            st = ntdll.NtWow64ReadVirtualMemory64(h, 0x140000000, buf, 8,
                                                  ctypes.byref(got64))
            p("      NtWow64ReadVirtualMemory64 status=%#010x" % (st & 0xFFFFFFFF))
        else:
            p("      NtWow64ReadVirtualMemory64 not exported by this ntdll")
        if HAVE_READ_EX:
            b2 = ctypes.create_string_buffer(16)
            g2 = ctypes.c_size_t(0)
            st = ntdll.NtReadVirtualMemoryEx(h, ctypes.c_void_p(0x140000000), b2,
                                             16, ctypes.byref(g2), 0)
            p("      NtReadVirtualMemoryEx      status=%#010x got=%d"
              % (st & 0xFFFFFFFF, g2.value))
        else:
            p("      NtReadVirtualMemoryEx not exported by this ntdll")
        if CONTROL_EXE:
            for cpid, cname in pids_named(CONTROL_EXE):
                ch = k32.OpenProcess(0x0410, False, cpid)
                if not ch:
                    p("      control %s(%d) OpenProcess err=%d"
                      % (cname, cpid, ctypes.get_last_error()))
                    continue
                cmods, _ = game_modules(cpid)
                base = cmods[0][1] if cmods else 0x400000
                craw, cst = ntrpm(ch, base, 16)
                p("      control %s(%d) base=%#012x NtRead=%#010x %s"
                  % (cname, cpid, base, cst, craw[:8].hex(" ") if craw else "no data"))
                k32.CloseHandle(ch)
        mods, note = game_modules(pid)
        p("      toolhelp modules: %s" % note)
        if mods:
            for nm, mb, ms in mods[:6]:
                p("         %-32s base=%#012x size=%#x" % (nm, mb, ms))

        p("   -- thread-level reads")
        snap = k32.CreateToolhelp32Snapshot(0x4, pid)  # TH32CS_SNAPTHREAD
        tids = [t for t in thread_ids(snap, pid)][:4]
        k32.CloseHandle(snap)
        p("      thread ids sampled: %s" % tids)
        for tid in tids:
            th = k32.OpenThread(0x0008 | 0x0010, False, tid)  # GET_CONTEXT|QUERY
            if not th:
                p("         tid=%d OpenThread err=%d" % (tid, ctypes.get_last_error()))
                continue
            ctx = CONTEXT64()
            ctx.ContextFlags = 0x00100001  # CONTEXT_AMD64|CONTEXT_CONTROL
            ok = k32.GetThreadContext(th, ctypes.byref(ctx))
            err = ctypes.get_last_error()
            p("         tid=%d GetThreadContext ok=%d err=%d rip=%#x rsp=%#x"
              % (tid, bool(ok), err, ctx.Rip, ctx.Rsp))
            if ok:
                raw, st = ntrpm(h, ctx.Rsp, 16)
                p("            NtRead(rsp)=%#010x %s"
                  % (st, raw[:8].hex(" ") if raw else ""))
            k32.CloseHandle(th)

        regs, calls, stop, err = image_regions(h)
        p("   -- VAD walk: calls=%d stop=%#x MEM_IMAGE regions=%d"
          % (calls, stop, len(regs)))
        big = sorted(regs, key=lambda r: -r[1])[:8]
        for b, s, pr in big:
            p("      base=%#012x size=%#010x prot=%#x" % (b, s, pr))
        low = sorted(regs)[:6]
        for b, s, pr in low:
            p("      low base=%#012x size=%#010x prot=%#x" % (b, s, pr))
        k32.CloseHandle(h)

    with open(REPORT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")


def thread_ids(snap, pid):
    """THREADENTRY32 is 28 bytes on x64."""
    class THREADENTRY32(ctypes.Structure):
        _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD),
                    ("th32ThreadID", wt.DWORD), ("th32OwnerProcessID", wt.DWORD),
                    ("tpBasePri", ctypes.c_long), ("tpDeltaPri", ctypes.c_long),
                    ("dwFlags", wt.DWORD)]

    te = THREADENTRY32()
    te.dwSize = ctypes.sizeof(te)
    ok = k32.Thread32First(snap, ctypes.byref(te))
    while ok:
        if te.th32OwnerProcessID == pid:
            yield te.th32ThreadID
        ok = k32.Thread32Next(snap, ctypes.byref(te))


main()
