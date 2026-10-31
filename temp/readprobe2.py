"""readprobe2.py -- control test + granted-access audit + handle-theft candidates.

readprobe1 result: every access mask gave the same 3 answers
  rpm   ERROR_INVALID_PARAMETER (87)
  plain 0xC000000D  (intercepted)
  Ex    0xC0000022  ACCESS_DENIED -> the handle really has no VM_READ
So the question is not "which mask", it is "does this machine read *anything*,
and does some process already hold a usable Apex handle I can duplicate".

  1. control: spawn notepad.exe, run the same primitives -> is the harness
     sound at all?  (expect: rpm ok)
  2. audit:   read our Apex handle's GrantedAccess out of the kernel's
     SystemExtendedHandleInformation -> proves/refutes the strip.
  3. theft:   list processes holding a Process-type handle to the Apex pid with
     PROCESS_VM_READ set -> duplicate candidates, then try a read on the clone.

Output: temp/readprobe2.txt
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import namehunt as nh

REPORT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "readprobe2.txt")
out = []


def p(s=""):
    out.append(s)


ntdll = ctypes.WinDLL("ntdll")
ntdll.NtQuerySystemInformation.argtypes = [ctypes.c_int, ctypes.c_void_p,
                                           ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong)]
ntdll.NtQuerySystemInformation.restype = ctypes.c_long
ntdll.NtQueryInformationProcess.argtypes = [wt.HANDLE, ctypes.c_int, ctypes.c_void_p,
                                            ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong)]
ntdll.NtQueryInformationProcess.restype = ctypes.c_long
nh.k32.DuplicateHandle.argtypes = [wt.HANDLE, wt.HANDLE, wt.HANDLE,
                                    ctypes.POINTER(wt.HANDLE), wt.DWORD, wt.BOOL,
                                    wt.DWORD]
nh.k32.DuplicateHandle.restype = wt.BOOL

PROCESS_VM_READ = 0x0010
DUPLICATE_SAME_ACCESS = 0x00000002
MAXIMUM_ALLOWED = 0x02000000
PROBE = 0x7FF720080000                     # image region found by readprobe.py


def handles():
    """[(owner_pid, handle_value, granted_access, type_index)] across the system."""
    size = 1 << 20
    for _ in range(8):
        buf = ctypes.create_string_buffer(size)
        need = ctypes.c_ulong(0)
        st = ntdll.NtQuerySystemInformation(64, buf, size, ctypes.byref(need))
        if st & 0xFFFFFFFF == 0xC0000004:        # INFO_LENGTH_MISMATCH
            size = max(need.value, size * 2)
            continue
        if st != 0:
            p("NtQuerySystemInformation(64) status=%#x" % (st & 0xFFFFFFFF))
            return []
        count = struct.unpack_from("<Q", buf.raw, 0)[0]
        base = ctypes.addressof(buf) + 16
        res = []
        for i in range(count):
            off = base + i * 40
            raw = ctypes.string_at(off, 32)
            owner, hval = struct.unpack_from("<QQ", raw, 8)
            granted, _cbi, tidx = struct.unpack_from("<IHH", raw, 24)
            res.append((owner, hval, granted, tidx))
        return res
    return []


def proc_pid(handle):
    """pid behind a process handle, or None."""
    buf = ctypes.create_string_buffer(0x30)
    need = ctypes.c_ulong(0)
    if ntdll.NtQueryInformationProcess(handle, 0, buf, 0x30,
                                       ctypes.byref(need)) != 0:
        return None
    return struct.unpack_from("<Q", buf.raw, 0)[0] & 0xFFFFFFFF


def control():
    """Spawn notepad and prove the read harness works on an unprotected process."""
    import subprocess
    import time
    p("## control: notepad.exe")
    pr = subprocess.Popen(["notepad.exe"])
    try:
        h = None
        for _ in range(50):
            if pr.poll() is not None:
                break
            h = nh.k32.OpenProcess(0x1F0FFF, False, pr.pid)
            if h:
                break
            time.sleep(0.1)
        if not h:
            p("  could not open notepad")
            return
        mbi = nh.MBI()
        probe = None
        addr = 0x10000
        while addr < 0x7FFFFFFEFFFF:
            if not nh.k32.VirtualQueryEx(h, ctypes.c_void_p(addr), ctypes.byref(mbi),
                                         ctypes.sizeof(mbi)):
                break
            if (mbi.State == nh.MEM_COMMIT and mbi.Type == nh.MEM_IMAGE
                    and (mbi.Protect & 0xFF) in nh.READABLE):
                probe = mbi.BaseAddress
                break
            addr = mbi.BaseAddress + mbi.RegionSize
        p("  pid=%d probe=%s" % (pr.pid, hex(probe) if probe else "?"))
        if probe:
            got = ctypes.c_size_t(0)
            buf = ctypes.create_string_buffer(2)
            ok = nh.k32.ReadProcessMemory(h, ctypes.c_void_p(probe), buf, 2,
                                          ctypes.byref(got))
            p("  rpm ok=%d err=%d bytes=%r" % (bool(ok), ctypes.get_last_error(),
                                               buf.raw[:got.value]))
            ssn, _ = nh.disk_export(
                os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                             "System32", "ntdll.dll"), "NtReadVirtualMemory")
            got2 = ctypes.c_size_t(0)
            st = nh.Syscall().stub(ssn)(h, ctypes.c_void_p(probe), buf, 2,
                                        ctypes.byref(got2), 0)
            p("  syscall status=%#x got=%d bytes=%r"
              % (st & 0xFFFFFFFF, got2.value, buf.raw[:got2.value]))
        nh.k32.CloseHandle(h)
    finally:
        pr.kill()


def enable_se_debug():
    """Elevated is not enough -- the token has to actually enable SeDebugPrivilege."""
    k32 = ctypes.windll.kernel32
    adv = ctypes.windll.advapi32
    ADV_TOKEN_ADJUST, ADV_TOKEN_QUERY = 0x20, 0x8

    class LUID(ctypes.Structure):
        _fields_ = [("Low", wt.DWORD), ("High", wt.LONG)]

    class TP(ctypes.Structure):
        _fields_ = [("Count", wt.DWORD), ("Luid", LUID), ("Attr", wt.DWORD)]

    adv.LookupPrivilegeValueW.argtypes = [wt.LPCWSTR, wt.LPCWSTR,
                                           ctypes.POINTER(LUID)]
    adv.LookupPrivilegeValueW.restype = wt.BOOL
    adv.OpenProcessToken.argtypes = [wt.HANDLE, wt.DWORD, ctypes.POINTER(wt.HANDLE)]
    adv.OpenProcessToken.restype = wt.BOOL
    k32.GetCurrentProcess.restype = wt.HANDLE
    adv.AdjustTokenPrivileges.argtypes = [wt.HANDLE, wt.BOOL, ctypes.c_void_p,
                                          wt.DWORD, ctypes.c_void_p, ctypes.c_void_p]
    adv.AdjustTokenPrivileges.restype = wt.BOOL
    htok = wt.HANDLE()
    if not adv.OpenProcessToken(k32.GetCurrentProcess(),
                                ADV_TOKEN_ADJUST | ADV_TOKEN_QUERY,
                                ctypes.byref(htok)):
        return "open-token err=%d" % ctypes.get_last_error()
    luid = LUID()
    if not adv.LookupPrivilegeValueW(None, "SeDebugPrivilege", ctypes.byref(luid)):
        return "lookup err=%d" % ctypes.get_last_error()
    tp = TP(1, luid, 0x2)
    ctypes.set_last_error(0)
    ok = adv.AdjustTokenPrivileges(htok, False, ctypes.byref(tp), 0, None, None)
    err = ctypes.get_last_error()
    k32.CloseHandle(htok)
    return "on" if (ok and err == 0) else "err=%d" % err


def steal(cand, pid, ex_ssn):
    """Duplicate every VM_READ handle to `pid`, then try rpm and the Ex syscall."""
    per = {}
    for owner, hv, granted, _t in cand:
        per.setdefault(owner, []).append((hv, granted))
    sysc = nh.Syscall()
    denied, worked = [], []
    for owner in sorted(per, key=lambda o: -len(per[o])):
        ho = nh.k32.OpenProcess(0x0040, False, owner)          # PROCESS_DUP_HANDLE
        if not ho:
            err = ctypes.get_last_error()
            ho = nh.k32.OpenProcess(0x1FFFFF, False, owner)
            if not ho:
                denied.append((owner, len(per[owner]), ctypes.get_last_error()))
                if len(per[owner]) >= 3:
                    p("  owner %-6d n=%-4d dup-open err=%d/%d"
                      % (owner, len(per[owner]), err, ctypes.get_last_error()))
                continue
        hits = 0
        for hv, granted in per[owner]:
            dup = wt.HANDLE()
            if not nh.k32.DuplicateHandle(ho, ctypes.c_void_p(hv),
                                          nh.k32.GetCurrentProcess(),
                                          ctypes.byref(dup), 0, False,
                                          MAXIMUM_ALLOWED):
                continue
            if proc_pid(dup) == pid:
                hits += 1
                got = ctypes.c_size_t(0)
                buf = ctypes.create_string_buffer(2)
                rpm = nh.k32.ReadProcessMemory(dup, ctypes.c_void_p(PROBE), buf, 2,
                                               ctypes.byref(got))
                rerr = ctypes.get_last_error()
                rbytes = buf.raw[:got.value]
                got2 = ctypes.c_size_t(0)
                buf2 = ctypes.create_string_buffer(2)
                st = sysc.stub(ex_ssn)(dup, ctypes.c_void_p(PROBE), buf2, 2,
                                       ctypes.byref(got2), 0)
                p("  owner %-6d h=%#x acc=%#x  rpm=%d/%d %r  ex=%#x/%d %r"
                  % (owner, hv, granted, bool(rpm), rerr, rbytes,
                     st & 0xFFFFFFFF, got2.value, buf2.raw[:got2.value]))
                worked.append((owner, hv, granted, bool(rpm), st & 0xFFFFFFFF))
            nh.k32.CloseHandle(dup)
        if hits == 0:
            if len(per[owner]) >= 20:
                p("  owner %-6d n=%-4d opened, no Apex handle" % (owner, len(per[owner])))
        nh.k32.CloseHandle(ho)
    return worked, denied


def main():
    pid = nh.find_pid(nh.EXE)
    p("## target")
    p("  exe=%s pid=%s" % (nh.EXE, pid))
    if not pid:
        return 1
    control()

    p("")
    p("## handle audit")
    p("  SeDebugPrivilege: %s" % enable_se_debug())
    me = os.getpid()
    h = nh.k32.OpenProcess(0x1F0FFF, False, pid)
    p("  our OpenProcess(0x1F0FFF) -> %s" % (hex(h) if h else "NULL"))
    hs = handles()
    p("  kernel handle entries: %d" % len(hs))
    tindex = None
    mine = [e for e in hs if e[0] == me and h and e[1] == h]
    if mine:
        _o, _hv, granted, tindex = mine[0]
        p("  granted access=%#x  VM_READ=%s  type_index=%d"
          % (granted, bool(granted & PROCESS_VM_READ), tindex))
    else:
        p("  our handle missing from the table")

    p("")
    p("## processes holding VM_READ on pid %d" % pid)
    cand = [e for e in hs
            if e[0] not in (0, 4, me)
            and (tindex is None or e[3] == tindex)
            and (e[2] & PROCESS_VM_READ)]
    p("  candidate entries: %d across %d owners"
      % (len(cand), len({e[0] for e in cand})))
    ex_ssn, _ = nh.disk_export(
        os.path.join(os.environ.get("SystemRoot", r"C:\Windows"),
                     "System32", "ntdll.dll"), "NtReadVirtualMemoryEx")
    p("  ssn NtReadVirtualMemoryEx=%s" % (hex(ex_ssn) if ex_ssn else "?"))
    worked, denied = steal(cand, pid, ex_ssn)
    p("")
    p("stolen+readable: %d" % len([w for w in worked if w[3]]))
    for w in worked:
        p("  %s" % (w,))
    p("still unreachable owners (PPL?): %s" % (denied[:8],))
    if h:
        nh.k32.CloseHandle(h)
    return 0


if __name__ == "__main__":
    rc = main()
    with open(REPORT, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    sys.exit(rc)
