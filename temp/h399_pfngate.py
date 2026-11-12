r"""h399 direct PTE bridge positive control, then Apex PEB->PE.
Existing gdrv3 only for physical reads and ordinary documented PFN query.
No DTB, new kernel driver, blanket RAM sweep or process write.
"""
import ctypes as C
import os
import struct
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio
import qk_va
import qk_gdrv_mapread
import dumplive as dl
import qk_pfn

OUT = os.path.join(ROOT, "temp", "h399_pfngate.txt")
PID = 14008


def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")


def live_pid():
    k = C.windll.kernel32
    k.CreateToolhelp32Snapshot.restype = C.c_void_p
    k.Process32FirstW.argtypes = [C.c_void_p, C.c_void_p]
    k.Process32NextW.argtypes = [C.c_void_p, C.c_void_p]
    class PE(C.Structure):
        _fields_ = [("dwSize", C.c_ulong), ("use", C.c_ulong),
                    ("id", C.c_ulong), ("heap", C.c_void_p),
                    ("mod", C.c_ulong), ("thr", C.c_ulong),
                    ("ppid", C.c_ulong), ("p", C.c_long),
                    ("flags", C.c_ulong), ("name", C.c_wchar * 260)]
    h = k.CreateToolhelp32Snapshot(2, 0)
    p = PE()
    p.dwSize = C.sizeof(p)
    found = 0
    if k.Process32FirstW(h, C.byref(p)):
        while True:
            if p.name == "r5apex_dx12.exe":
                found = p.id
                break
            if not k.Process32NextW(h, C.byref(p)):
                break
    k.CloseHandle(h)
    return found


open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
say("H399 PFN translation with gdrv3 MapK %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
g = gio.Gio(chunk=0x1000)
mr = qk_gdrv_mapread.install(g)
g.read_phys = mr.read
page = C.create_string_buffer(b"H399_MAPK_CONTROL_290318")
try:
    info = qk_pfn.pa_of(C.addressof(page))
    say("local status=0x%08X info=%s" % (info["status"],
            {k: hex(v) if isinstance(v, int) else v.hex()
             for k, v in info.items() if k != "raw"}))
    direct = C.addressof(page)
    if info["status"] != 0:
        say("VERDICT: BLOCKED - Windows PFN query refused")
        sys.exit(3)
    pfn_pa = (info["pfn"] & 0xFFFFFFFFFFF000) | (direct & 0xFFF)
    if not mr.in_ram(pfn_pa & ~0xFFF, 0x1000):
        say("guard refused=%#x" % pfn_pa)
        sys.exit(4)
    raw = g.read_phys(pfn_pa & ~0xFFF, 0x1000)
    offset = pfn_pa & 0xFFF
    say("local marker readback=%r" % raw[offset:offset + 24])
    control_ok = raw[offset:offset + 24] == b"H399_MAPK_CONTROL_290318"
    say("LOCAL_TRANSLATION_MATCH=%s" % control_ok)
    if not control_ok:
        say("VERDICT: BLOCKED - PFN result not trustworthy")
        sys.exit(4)
    pid = live_pid()
    if not pid:
        say("game absent")
        sys.exit(2)
    PID = pid
    peb = qk_va._peb_va(PID)
    say("current PID=%d PEB=%#x" % (PID, peb or 0))
    pebinfo = qk_pfn.pa_of(peb + 0x10)
    if pebinfo["status"] != 0:
        say("PEB PFN refused status=%#x" % pebinfo["status"])
        sys.exit(5)
    pa = (pebinfo["pfn"] & 0xFFFFFFFFFFF000) | ((peb + 0x10) & 0xFFF)
    b = g.read_phys(pa & ~0xFFF, 0x1000)
    base = struct.unpack_from("<Q", b, pa & 0xFFF)[0]
    say("game base=%#x" % base)
    info = qk_pfn.pa_of(base)
    if info["status"]:
        say("module PFN refused=%#x" % info["status"])
        sys.exit(5)
    ba = info["pfn"] & 0xFFFFFFFFFFFFF000
    profile = dl.validate_pe(g.read_phys(ba, 0x1000))
    say("RESULT: image_va=%#x image_pa=%#x meta=%s" % (base, ba, profile))
    say("VERDICT: %s" % ("PASS - VA translation without DTB"
        if profile and profile["size"] == 0xDFB8000 else "BLOCKED"))
finally:
    g.close()