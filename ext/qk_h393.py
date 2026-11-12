r"""qk_h393.py -- read-only EPROCESS discovery repair, gdrv3 only.

Control and game are intentionally the same code path.  Default control is
PowerShell; do not do a whole-RAM sweep until cached/raw object bytes rule out
locating a validated process object near its ImageFileName.  Every actual PA
read is restricted to the complete OS memory interval set (R10).  Success only
with PEB->image->valid PE in the chosen process's own page tables.
"""
import ctypes as C
import ctypes.wintypes as wt
import os
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import gio
import dumplive as dl
import qk_va


def arg(name, default):
    for a in sys.argv:
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
    return default


TARGET = arg("name", "r5apex_dx12.exe")
PID = int(arg("pid", str(dl.find_pid())), 0) if "--pid" not in sys.argv else 14008
OUT = os.path.join(ROOT, "temp", "qk_h393.txt")


def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")


def pid_and_peb(exe):
    class PEBasic(C.Structure):
        _fields_ = [("status", C.c_void_p), ("peb", C.c_void_p),
                    ("affinity", C.c_size_t), ("priority", C.c_long),
                    ("uniqueid", C.c_size_t), ("parent", C.c_size_t)]
    k = C.windll.kernel32
    ntdll = C.windll.ntdll
    k.CreateToolhelp32Snapshot.restype = C.c_void_p
    k.Process32FirstW.argtypes = [C.c_void_p, C.c_void_p]
    k.Process32NextW.argtypes = [C.c_void_p, C.c_void_p]
    k.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
    k.OpenProcess.restype = C.c_void_p
    class PE32(C.Structure):
        _fields_ = [("size", wt.DWORD), ("usage", wt.DWORD), ("pid", wt.DWORD),
                    ("heap", C.c_void_p), ("modid", wt.DWORD), ("threads", wt.DWORD),
                    ("ppid", wt.DWORD), ("prio", C.c_long), ("flags", wt.DWORD),
                    ("name", wt.WCHAR * 260)]
    snap = k.CreateToolhelp32Snapshot(2, 0)
    p = PE32()
    p.size = C.sizeof(p)
    ids = []
    if k.Process32FirstW(snap, C.byref(p)):
        while True:
            if p.name.lower() == exe.lower():
                ids.append(int(p.pid))
            if not k.Process32NextW(snap, C.byref(p)):
                break
    k.CloseHandle(snap)
    if not ids:
        raise OSError("process not found: %s" % exe)
    pid = ids[0] if exe.lower() == "r5apex_dx12.exe" else os.getpid()
    h = k.OpenProcess(0x1000, False, pid)
    if not h:
        raise OSError("query-only pid handle failed")
    b = PEBasic()
    st = ntdll.NtQueryInformationProcess(C.c_void_p(h), 0, C.byref(b), C.sizeof(b), None)
    k.CloseHandle(h)
    if st != 0:
        raise OSError("query PEB failed status=%x" % (st & 0xFFFFFFFF))
    return pid, b.peb


open(OUT, "w", encoding="ascii").close()
dl.NAME = (b"r5apex_dx12.ex\0" if TARGET.lower() == "r5apex_dx12.exe"
           else (b"powershell.exe\0" if TARGET.lower() == "powershell.exe"
                 else TARGET.encode("ascii", "replace") + b"\0"))
if not dl.elevation():
    cmd = " ".join('"' + a + '"' for a in [os.path.abspath(__file__)] + sys.argv[1:])
    sys.exit(dl.run_elevated(cmd))
say("=== h393 object-and-translation repair %s name=%s ===" %
    (time.strftime("%Y-%m-%d %H:%M:%S"), TARGET))
pid, peb = pid_and_peb(TARGET)
say("PID=%d PEB=%#x elevated=%d" % (pid, peb, dl.elevation()))
g = gio.Gio(chunk=0x1000)
ranges, note = dl.usable_ranges(g.ram_top, None, None)
ram = qk_va.Ram(ranges)
g.is_ram = ram.page_ok
say("ranges=%d note=%s memtop=%#x" % (len(ranges), note, g.ram_top))
# The established proc-tag recipe validates BOTH layouts when local notes allow
# either. Use it itself rather than re-interpreting memory offset guesses.
import importlib.util
spec = importlib.util.spec_from_file_location("h142", os.path.join(ROOT, "temp", "_p142.py"))
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
h.OUT = os.path.join(ROOT, "temp", "_h393_proc.txt")
h.CAL_OK[:] = []
h._f = open(os.path.join(ROOT, "temp", "_h393_proc.txt"), "w", encoding="ascii")
dtb, seeds = h.find_dtb(g, pid, budget=100.0, seeds=[], proctag=True)
say("established_locator_dtb=%s seeds=%d" % (hex(dtb) if dtb else "none", len(seeds)))
if dtb:
    try:
        rd = qk_va.Reader(g, dtb)
        raw = rd.read(peb + 0x10, 8)
        say("PEB_IMAGE_BASE raw=%r" % raw)
        if raw:
            base = struct.unpack("<Q", raw)[0]
            b = rd.read(base, 0x1000)
            meta = dl.validate_pe(b) if b else None
            say("IMAGE=%#x PE=%s" % (base, meta))
            say("RESULT: image_pa=%s" % rd.page_pa(base))
            say("VERDICT: PASS" if meta else "VERDICT: PARTIAL")
            sys.exit(0 if meta else 3)
    except OSError as e:
        say("WALK=%s" % e)
say("VERDICT: BLOCKED - process locator did not establish translation")
g.close()