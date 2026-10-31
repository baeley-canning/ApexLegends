"""mods.py -- how do we find the image base of a live, EAC-protected Apex?

globals.txt says: toolhelp module snapshot err=87, PEB->ImageBaseAddress
unreadable.  One of those is a ctypes detail and the other is a real fact, and
guessing between them is how a cheat ends up reading garbage.  So measure:

  * VirtualQueryEx walk of the whole address space -> every MEM_IMAGE region,
    with its PE TimeDateStamp / SizeOfImage / first section sizes.  The main
    image is the one whose TimeDateStamp matches the on-disk exe.
  * ReadProcessMemory at the PEB and at 0x140000000: does RPM work at all?
  * CreateToolhelp32Snapshot with 0x8, 0x10 and 0x18 separately, plus
    EnumProcessModulesEx, so we learn which one this process tolerates.

Elevated only (the game runs elevated).  Output: temp/mods.txt
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = "r5apex_dx12.exe"
ON_DISK = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
REPORT = os.path.join(HERE, "mods.txt")

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
psapi = ctypes.WinDLL("psapi", use_last_error=True)


class MBI(ctypes.Structure):
    _fields_ = [("BaseAddress", ctypes.c_ulonglong),
                ("AllocationBase", ctypes.c_ulonglong),
                ("AllocationProtect", wt.DWORD), ("__a1", wt.DWORD),
                ("RegionSize", ctypes.c_ulonglong),
                ("State", wt.DWORD), ("Protect", wt.DWORD),
                ("Type", wt.DWORD), ("__a2", wt.DWORD)]


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
                ("ProccntUsage", wt.DWORD),
                ("modBaseAddr", ctypes.POINTER(ctypes.c_byte)),
                ("modBaseSize", wt.DWORD), ("hModule", wt.HMODULE),
                ("szModule", wt.WCHAR * 256), ("szExePath", wt.WCHAR * 260)]


k32.VirtualQueryEx.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.POINTER(MBI),
                                ctypes.c_size_t]
k32.VirtualQueryEx.restype = ctypes.c_size_t
k32.ReadProcessMemory.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                   ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
k32.ReadProcessMemory.restype = wt.BOOL

MEM_IMAGE, MEM_COMMIT = 0x1000000, 0x1000


def find_pid(exe):
    snap = k32.CreateToolhelp32Snapshot(0x2, 0)
    pe = PROCESSENTRY32W()
    pe.dwSize = ctypes.sizeof(pe)
    try:
        ok = k32.Process32FirstW(snap, ctypes.byref(pe))
        while ok:
            if pe.szExeFile.lower() == exe.lower():
                return pe.th32ProcessID
            ok = k32.Process32NextW(snap, ctypes.byref(pe))
    finally:
        k32.CloseHandle(snap)
    return None


def rpm(h, addr, n):
    buf = ctypes.create_string_buffer(n)
    got = ctypes.c_size_t(0)
    ok = k32.ReadProcessMemory(h, ctypes.c_void_p(addr), buf, n, ctypes.byref(got))
    return buf.raw[:got.value] if ok else None


def on_disk_stamp():
    with open(ON_DISK, "rb") as fh:
        head = fh.read(0x400)
    e = struct.unpack_from("<I", head, 0x3C)[0]
    stamp = struct.unpack_from("<I", head, e + 8)[0]
    size = struct.unpack_from("<I", head, e + 24 + 56)[0]
    return stamp, size


def pe_info(raw):
    if not raw or raw[:2] != b"MZ" or len(raw) < 0x200:
        return None
    e = struct.unpack_from("<I", raw, 0x3C)[0]
    if e + 0x100 > len(raw) or raw[e:e + 4] != b"PE\0\0":
        return None
    stamp = struct.unpack_from("<I", raw, e + 8)[0]
    nsec = struct.unpack_from("<H", raw, e + 6)[0]
    optsz = struct.unpack_from("<H", raw, e + 20)[0]
    opt = e + 24
    size = struct.unpack_from("<I", raw, opt + 56)[0]
    secs = []
    for i in range(min(nsec, 3)):
        o = opt + optsz + i * 40
        if o + 24 > len(raw):
            break
        name = raw[o:o + 8].rstrip(b"\0").decode("latin-1")
        vsize, va = struct.unpack_from("<II", raw, o + 8)
        secs.append((name, va, vsize))
    return {"stamp": stamp, "size": size, "secs": secs}


def write(out):
    text = "\n".join(out) + "\n"
    with open(REPORT, "w", encoding="utf-8") as fh:
        fh.write(text)
    sys.stdout.write(text)



def main():
    out = []

    def p(s=""):
        out.append(s)

    pid = find_pid(EXE)
    p("# mods probe  pid=%s" % pid)
    stamp, dsize = on_disk_stamp()
    p("# on-disk exe: timestamp=%#x sizeofimage=%#x" % (stamp, dsize))
    if not pid:
        write(out)
        return
    h = k32.OpenProcess(0x0410, False, pid)
    p("# handle=%s err=%d" % (h, ctypes.get_last_error()))
    if not h:
        write(out)
        return

    # ---- toolhelp variants ----------------------------------------------
    p("")
    p("## CreateToolhelp32Snapshot module variants")
    for flags in (0x8, 0x10, 0x18):
        snap = k32.CreateToolhelp32Snapshot(flags, pid)
        p("  flags=%#04x snap=%s" % (flags, snap))
        if snap in (-1, 0, 0xFFFFFFFFFFFFFFFF):
            p("      FAIL err=%d" % ctypes.get_last_error())
            continue
        me = MODULEENTRY32W()
        me.dwSize = ctypes.sizeof(me)
        names, n = [], 0
        ok = k32.Module32FirstW(snap, ctypes.byref(me))
        while ok and n < 300:
            names.append((me.szModule,
                          ctypes.cast(me.modBaseAddr, ctypes.c_void_p).value,
                          me.modBaseSize))
            n += 1
            ok = k32.Module32NextW(snap, ctypes.byref(me))
        k32.CloseHandle(snap)
        p("      modules=%d err=%d" % (len(names), ctypes.get_last_error()))
        for nm, b, s in names[:6]:
            p("      %-30s base=%#x size=%#x" % (nm, b, s))
        hit = [x for x in names if x[0].lower() == EXE.lower()]
        if hit:
            p("      >>> MATCH base=%#x size=%#x" % (hit[0][1], hit[0][2]))

    # ---- psapi ----------------------------------------------------------
    p("")
    p("## EnumProcessModulesEx(LIST_MODULES_ALL=3)")
    arr = (wt.HMODULE * 512)()
    need = wt.DWORD(0)
    ok = psapi.EnumProcessModulesEx(h, ctypes.byref(arr), ctypes.sizeof(arr),
                                    ctypes.byref(need), 3)
    cnt = need.value // ctypes.sizeof(wt.HMODULE)
    p("  ok=%d err=%d count=%d" % (bool(ok), ctypes.get_last_error(), cnt))
    for i in range(min(cnt, 8)):
        buf = ctypes.create_unicode_buffer(280)
        name = buf.value
        if not psapi.GetModuleBaseNameW(h, arr[i], buf, 280):
            name = "?"
        info = pe_info(rpm(h, arr[i], 0x400))
        p("  %-30s base=%#x stamp=%s size=%s"
          % (name, arr[i], hex(info["stamp"]) if info else "?",
             hex(info["size"]) if info else "?"))

    # ---- PEB ------------------------------------------------------------
    class PBI(ctypes.Structure):
        _fields_ = [("R1", ctypes.c_void_p), ("Peb", ctypes.c_void_p),
                    ("R2", ctypes.c_void_p * 2), ("Pid", ctypes.c_void_p),
                    ("R3", ctypes.c_void_p)]

    ntdll = ctypes.WinDLL("ntdll")
    pbi = PBI()
    ret = ctypes.c_ulong(0)
    st = ntdll.NtQueryInformationProcess(h, 0, ctypes.byref(pbi),
                                         ctypes.sizeof(pbi), ctypes.byref(ret))
    p("")
    p("## PEB")
    p("  status=%#x peb=%#x" % (st, pbi.Peb or 0))
    if pbi.Peb:
        raw = rpm(h, pbi.Peb, 0x40)
        p("  rpm(peb,0x40)=%s" % ("FAIL" if raw is None else "ok"))
        if raw:
            for i in range(0, len(raw), 8):
                p("      +%#04x %#014x" % (i, struct.unpack_from("<Q", raw, i)[0]))
            p("  image base @peb+0x10 = %#x"
              % struct.unpack_from("<Q", raw, 0x10)[0])

    # ---- address space walk ---------------------------------------------
    p("")
    p("## MEM_IMAGE regions (PE headers parsed through RPM)")
    addr, hits = 0, []
    mbi = MBI()
    while addr < 0x7FFFFFFFFFFF:
        got = k32.VirtualQueryEx(h, ctypes.c_void_p(addr), ctypes.byref(mbi),
                                  ctypes.sizeof(mbi))
        if not got:
            break
        if mbi.State == MEM_COMMIT and mbi.Type == MEM_IMAGE:
            info = pe_info(rpm(h, mbi.BaseAddress, 0x400))
            if info:
                first = info["secs"][0] if info["secs"] else ("?", 0, 0)
                p("  base=%#012x size=%#09x stamp=%#x img=%#x %s va=%#x vs=%#x"
                  % (mbi.BaseAddress, mbi.RegionSize, info["stamp"], info["size"],
                     first[0], first[1], first[2]))
                hits.append((mbi.BaseAddress, info))
        nxt = mbi.BaseAddress + mbi.RegionSize
        if nxt <= addr:
            break
        addr = nxt
    p("  regions with PE headers: %d" % len(hits))

    p("")
    p("## region matching the on-disk exe timestamp")
    for base, info in hits:
        if info["stamp"] == stamp:
            p("  MATCH base=%#x sizeofimage=%#x (disk %#x)"
              % (base, info["size"], dsize))
    p("")
    raw = rpm(h, 0x140000000, 0x40)
    p("## RPM test at 0x140000000: %s"
      % ("FAIL" if raw is None else "ok " + raw[:16].hex(" ")))
    write(out)


main()
