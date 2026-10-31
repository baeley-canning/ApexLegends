"""diag6.py -- why is the read refused?  (PPL hypothesis)

diag5 findings:
  * eaanticheat.sys loaded, service EAAntiCheat running, 7 EAC processes
  * NtRead/NtWrite -> 0xC000000D for EVERY access mask (also through a
    duplicated handle) -- so it is not about the requested rights
  * NtReadVirtualMemoryEx -> 0xC0000022 (ACCESS_DENIED)  <- different status
  * GetThreadContext -> err 5 for all sampled threads
  * VirtualQueryEx VAD walk -> fine, 1279 MEM_IMAGE regions
  * control explorer.exe -> NtRead ok, "MZ" header

Two competing explanations:
  A. EAC hooks the Nt*VirtualMemory path in the kernel and hands back a bogus
     status for the protected target.
  B. the game is a Protected Process Light: PROCESS_VM_READ is silently
     stripped from the handle, so the *real* read returns ACCESS_DENIED.
     The 0xC0000022 from the un-hooked NtReadVirtualMemoryEx is the clue.

diag6 asks:
  1. does the game handle actually carry VM_READ?     (NtQueryInformationProcess
     class 0 -> GrantedAccess in the returned block)
  2. is the game PPL, and with which signer?          (class 61)
  3. does enabling SeDebugPrivilege change the outcome?
  4. does NtReadVirtualMemoryEx work on a control process with the same
     requested rights (is the primitive itself sound)?
  5. does NtQueryVirtualMemory still describe the game's image?
  6. does a 32-bit style query (ProcessWow64Information) say anything?

Output: temp/diag6.txt
"""

import ctypes
import ctypes.wintypes as wt
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = "r5apex_dx12.exe"
CONTROL_EXE = "explorer.exe"
REPORT = os.path.join(HERE, "diag6.txt")

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
ntdll = ctypes.WinDLL("ntdll")
adv = ctypes.WinDLL("advapi32", use_last_error=True)

k32.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
k32.OpenProcess.restype = wt.HANDLE
k32.CloseHandle.argtypes = [wt.HANDLE]
k32.CloseHandle.restype = wt.BOOL
k32.GetCurrentProcess.restype = wt.HANDLE
k32.OpenProcessToken.argtypes = [wt.HANDLE, wt.DWORD, ctypes.POINTER(wt.HANDLE)]
k32.OpenProcessToken.restype = wt.BOOL
adv.LookupPrivilegeValueW.argtypes = [wt.LPCWSTR, wt.LPCWSTR,
                                       ctypes.POINTER(ctypes.c_longlong)]
adv.LookupPrivilegeValueW.restype = wt.BOOL
adv.AdjustTokenPrivileges.argtypes = [wt.HANDLE, wt.BOOL, ctypes.c_void_p,
                                       wt.DWORD, ctypes.c_void_p, ctypes.c_void_p]
adv.AdjustTokenPrivileges.restype = wt.BOOL

ntdll.NtQueryInformationProcess.argtypes = [wt.HANDLE, wt.ULONG, ctypes.c_void_p,
                                            wt.ULONG, ctypes.POINTER(wt.ULONG)]
ntdll.NtQueryInformationProcess.restype = ctypes.c_long
ntdll.NtReadVirtualMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                      ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
ntdll.NtReadVirtualMemory.restype = ctypes.c_long
ntdll.NtQueryVirtualMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, wt.ULONG,
                                       ctypes.c_void_p, ctypes.c_size_t,
                                       ctypes.POINTER(ctypes.c_size_t)]
ntdll.NtQueryVirtualMemory.restype = ctypes.c_long
try:
    ntdll.NtReadVirtualMemoryEx.argtypes = [wt.HANDLE, ctypes.c_void_p,
                                            ctypes.c_void_p, ctypes.c_size_t,
                                            ctypes.POINTER(ctypes.c_size_t),
                                            wt.ULONG]
    ntdll.NtReadVirtualMemoryEx.restype = ctypes.c_long
    HAVE_READ_EX = True
except AttributeError:
    HAVE_READ_EX = False

out = []


def p(s=""):
    print(s)
    out.append(s)



class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD),
                ("th32ProcessID", wt.DWORD), ("th32DefaultHeapID", ctypes.c_size_t),
                ("th32ModuleID", wt.DWORD), ("cntThreads", wt.DWORD),
                ("th32ParentProcessID", wt.DWORD), ("pcPriClassBase", ctypes.c_long),
                ("dwFlags", wt.DWORD), ("szExeFile", ctypes.c_wchar * 260)]


k32.CreateToolhelp32Snapshot.argtypes = [wt.DWORD, wt.DWORD]
k32.CreateToolhelp32Snapshot.restype = wt.HANDLE
k32.Process32FirstW.argtypes = [wt.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
k32.Process32FirstW.restype = wt.BOOL
k32.Process32NextW.argtypes = [wt.HANDLE, ctypes.POINTER(PROCESSENTRY32W)]
k32.Process32NextW.restype = wt.BOOL


def pids_named(exe):
    snap = k32.CreateToolhelp32Snapshot(0x2, 0)
    pe = PROCESSENTRY32W()
    pe.dwSize = ctypes.sizeof(pe)
    found = []
    ok = k32.Process32FirstW(snap, ctypes.byref(pe))
    while ok:
        if pe.szExeFile.lower() == exe.lower():
            found.append(pe.th32ProcessID)
        ok = k32.Process32NextW(snap, ctypes.byref(pe))
    k32.CloseHandle(snap)
    return found


class LUID(ctypes.Structure):
    _fields_ = [("LowPart", wt.DWORD), ("HighPart", ctypes.c_long)]


class LUID_AND_ATTRIBUTES(ctypes.Structure):
    _fields_ = [("Luid", LUID), ("Attributes", wt.DWORD)]


class TOKEN_PRIVILEGES(ctypes.Structure):
    _fields_ = [("PrivilegeCount", wt.DWORD),
                ("Privileges", LUID_AND_ATTRIBUTES * 8)]


def enable_privilege(name):
    """Returns (enabled, err)."""
    tok = wt.HANDLE()
    if not k32.OpenProcessToken(k32.GetCurrentProcess(), 0x0020 | 0x0008,
                                ctypes.byref(tok)):
        return None, ctypes.get_last_error()
    luid = ctypes.c_longlong(0)
    if not adv.LookupPrivilegeValueW(None, name, ctypes.byref(luid)):
        err = ctypes.get_last_error()
        k32.CloseHandle(tok)
        return None, err
    tp = TOKEN_PRIVILEGES()
    tp.PrivilegeCount = 1
    tp.Privileges[0].Luid.LowPart = luid.value & 0xFFFFFFFF
    tp.Privileges[0].Luid.HighPart = (luid.value >> 32) & 0xFFFFFFFF
    tp.Privileges[0].Attributes = 0x00000002  # SE_PRIVILEGE_ENABLED
    ok = adv.AdjustTokenPrivileges(tok, False, ctypes.byref(tp),
                                   ctypes.sizeof(tp), None, None)
    err = ctypes.get_last_error()  # 1300 == not all privileges assigned
    k32.CloseHandle(tok)
    return (bool(ok) and err == 0), err


def granted_access(h):
    """class 0 -> PROCESS_BASIC_INFORMATION (UniqueProcessId@0x20,
    GrantedAccess@0x30 on win8.1+).  Returns (raw_block|None, status, len)."""
    buf = ctypes.create_string_buffer(64)
    n = wt.ULONG(0)
    st = ntdll.NtQueryInformationProcess(h, 0, buf, ctypes.sizeof(buf),
                                         ctypes.byref(n))
    return (buf.raw if st == 0 else None), st & 0xFFFFFFFF, n.value


def protection(h):
    """class 61 -> one PS_PROTECTION byte (7-bit type, 1 audit bit, 4-bit signer)."""
    buf = ctypes.create_string_buffer(8)
    n = wt.ULONG(0)
    st = ntdll.NtQueryInformationProcess(h, 61, buf, ctypes.sizeof(buf),
                                         ctypes.byref(n))
    if st != 0:
        return None, st & 0xFFFFFFFF, n.value
    b = buf.raw[0]
    return (b & 0x07, (b >> 3) & 0x01, (b >> 4) & 0x0F), 0, n.value


PROT_TYPE = {0: "none", 1: "light(PPL)", 2: "full(PP)"}
PROT_SIGNER = {0: "none", 1: "authenticode", 2: "codegen", 3: "antimalware",
               4: "lsa", 5: "windows", 6: "winTcb", 7: "winSystem",
               8: "app", 9: "appLsa", 10: "appWinTcb"}


class MBI(ctypes.Structure):
    _fields_ = [("BaseAddress", ctypes.c_void_p), ("AllocationBase", ctypes.c_void_p),
                ("AllocationProtect", wt.DWORD), ("PartitionId", wt.WORD),
                ("RegionSize", ctypes.c_size_t), ("State", wt.DWORD),
                ("Protect", wt.DWORD), ("Type", wt.DWORD)]


k32.VirtualQueryEx.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.POINTER(MBI),
                                ctypes.c_size_t]
k32.VirtualQueryEx.restype = ctypes.c_size_t


def first_image_base(h, budget=200000):
    addr, calls = 0x10000, 0
    while calls < budget:
        mbi = MBI()
        if not k32.VirtualQueryEx(h, ctypes.c_void_p(addr), ctypes.byref(mbi),
                                  ctypes.sizeof(mbi)):
            return None, calls
        calls += 1
        if not mbi.BaseAddress:
            return None, calls
        if mbi.Type == 0x1000000:
            return mbi.BaseAddress, calls
        nxt = mbi.BaseAddress + mbi.RegionSize
        if nxt <= addr:
            return None, calls
        addr = nxt
    return None, calls


def ntrpm(h, addr, n=8):
    buf = ctypes.create_string_buffer(n)
    got = ctypes.c_size_t(0)
    st = ntdll.NtReadVirtualMemory(h, ctypes.c_void_p(addr), buf, n,
                                   ctypes.byref(got))
    return (buf.raw[:got.value] if st == 0 else None), st & 0xFFFFFFFF, got.value


def ntread_ex(h, addr, n=8):
    buf = ctypes.create_string_buffer(n)
    got = ctypes.c_size_t(0)
    st = ntdll.NtReadVirtualMemoryEx(h, ctypes.c_void_p(addr), buf, n,
                                     ctypes.byref(got), 0)
    return (buf.raw[:got.value] if st == 0 else None), st & 0xFFFFFFFF, got.value


class UNICODE_STRING(ctypes.Structure):
    _fields_ = [("Length", wt.USHORT), ("MaximumLength", wt.USHORT),
                ("Buffer", ctypes.c_void_p)]


def mapped_name(h, addr):
    """NtQueryVirtualMemory(MemoryMappedFilenameInformation=2)."""
    buf = ctypes.create_string_buffer(0x500)
    got = ctypes.c_size_t(0)
    st = ntdll.NtQueryVirtualMemory(h, ctypes.c_void_p(addr), 2, buf,
                                    ctypes.sizeof(buf), ctypes.byref(got))
    if st != 0:
        return None, st & 0xFFFFFFFF
    us = UNICODE_STRING.from_buffer_copy(buf.raw[:ctypes.sizeof(UNICODE_STRING)])
    name = ctypes.wstring_at(us.Buffer, us.Length // 2) if us.Buffer else ""
    return name, 0


FLAGS = [(0x0010, "VM_READ"), (0x0008, "VM_OPERATION"), (0x0004, "VM_WRITE"),
         (0x0400, "QUERY_INFORMATION"), (0x1000, "QUERY_LIMITED"),
         (0x0040, "DUP_HANDLE"), (0x0100, "SET_INFORMATION"),
         (0x00100000, "SYNCHRONIZE")]


def flag_text(ga):
    if ga is None:
        return "n/a"
    return "|".join(n for b, n in FLAGS if ga & b) or "none"



def is_admin():
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def describe(pid, label):
    p("")
    p("## %s pid=%d" % (label, pid))
    h = k32.OpenProcess(0x1FFFFF, False, pid)
    if not h:
        p("   OpenProcess(ALL_ACCESS) err=%d" % ctypes.get_last_error())
        return
    blk, st, nlen = granted_access(h)
    if blk is None:
        p("   GrantedAccess query status=%#010x" % st)
    else:
        q = lambda off: struct.unpack_from("<Q", blk, off)[0]
        p("   requested 0x1fffff -> GrantedAccess=%#x (%s)  [len=%d]"
          % (q(0x30), flag_text(q(0x30)), nlen))
        p("   block: exit=%#x peb=%#x aff=%#x prio=%#x pid=%d ppid=%d ga=%#x"
          % (q(0x00), q(0x08), q(0x10), q(0x18), q(0x20), q(0x28), q(0x30)))
        p("   VM_READ present: %s   QUERY_INFORMATION present: %s"
          % (bool(q(0x30) & 0x0010), bool(q(0x30) & 0x0400)))
    pr, pst, plen = protection(h)
    if pr is None:
        p("   NtQueryInformationProcess(61) status=%#010x len=%d" % (pst, plen))
    else:
        typ, aud, sig = pr
        p("   PS_PROTECTION type=%d(%s) audit=%d signer=%d(%s) [len=%d]"
          % (typ, PROT_TYPE.get(typ, "?"), aud, sig,
             PROT_SIGNER.get(sig, "?"), plen))
    base, calls = first_image_base(h)
    p("   first MEM_IMAGE base=%s after %d VQ calls"
      % (("%#x" % base) if base else "none", calls))
    if base:
        raw, rst, got = ntrpm(h, base, 8)
        p("   NtReadVirtualMemory(%#x)=%#010x got=%d %s"
          % (base, rst, got, raw.hex(" ") if raw else ""))
        if HAVE_READ_EX:
            xraw, xst, xgot = ntread_ex(h, base, 8)
            p("   NtReadVirtualMemoryEx   (%#x)=%#010x got=%d %s"
              % (base, xst, xgot, xraw.hex(" ") if xraw else ""))
        nm, nst = mapped_name(h, base)
        p("   NtQueryVirtualMemory(2) status=%#010x name=%s" % (nst, nm))
    k32.CloseHandle(h)


def main():
    p("# diag6  admin=%s pid=%d  winver=%s"
      % (is_admin(), os.getpid(), sys.getwindowsversion()))
    ok, err = enable_privilege("SeDebugPrivilege")
    p("SeDebugPrivilege enabled=%s err=%d" % (ok, err))
    if HAVE_READ_EX:
        p("NtReadVirtualMemoryEx exported: yes")
    else:
        p("NtReadVirtualMemoryEx exported: no")

    targets = pids_named(EXE)
    if not targets:
        p("%s not running" % EXE)
    for pid in targets:
        describe(pid, "target")
    for pid in pids_named(CONTROL_EXE):
        describe(pid, "control")
    for pid in pids_named("EACefSubProcess.exe"):
        describe(pid, "eac helper")


if __name__ == "__main__":
    try:
        main()
    finally:
        with open(REPORT, "w", encoding="utf-8") as fh:
            fh.write("\n".join(out) + "\n")
        print("wrote", REPORT)

