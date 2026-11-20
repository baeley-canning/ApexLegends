# -*- coding: utf-8 -*-
r"""h413_live_dtb_ab.py -- machinery A/B against LIVE (non-game) processes.

Improves on h412 (whose only cached specimens belonged to dead pids and whose
tables had been recycled -- a design confound).  One variable:
VAR=live_process_dtb.  Pick alive, EAAC-unprotected processes (explorer.exe,
dwm.exe, ...), carve their EPROCESS in phys mem (name@0x338-family, type byte 3,
PriorityClass +0x347, UniqueProcessId hunt, DTB=base+0x28 -- the _qk_dtb14
method), then walk PEB -> ImageBase -> 'MZ'.  No game, no Apex, no driver ops.

  MACHINERY_SANE   >=1 live process walked to a real MZ  -> walks+phys reads+
                                                            carving all work;
                                                            yesterday's 0-hit
                                                            result is a game/
                                                            config/flow issue
  DAMAGED          live carves succeed but zero MZ reachable -> walk machinery
                     or transport damaged -> reboot justified
  CARVE_ZERO       no EPROCESS carved -> different failure, report honestly
  TRANSPORT_DOWN   gio unusable from this shell

Read-only throughout; R10 guard on every hop; bounded walks (p331).
Outputs: h413_live_dtb_ab.txt (+ _console/_err tee via caller).
"""
import ctypes
import os
import struct
import sys
import time
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio                       # noqa: E402
import dumplive as dl            # noqa: E402
import qk_va as VA               # noqa: E402

OUT = os.path.join(HERE, "h413_live_dtb_ab.txt")
_f = open(OUT, "w", encoding="utf-8")
_f.close()

PREF = ["explorer.exe", "dwm.exe", "cmd.exe", "notepad.exe", "python.exe",
        "steam.exe", "msedgewebview2.exe", "svchost.exe"]


def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(str(s) + "\n")


TH32CS_SNAPPROCESS = 0x2


class PENTRY(ctypes.Structure):
    _fields_ = [("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD),
                ("th32ProcessID", wintypes.DWORD),
                ("th32DefaultHeap", ctypes.c_size_t),   # ULONG_PTR, 8 B on x64
                ("th32ModuleID", wintypes.DWORD),
                ("cntThreads", wintypes.DWORD),
                ("th32ParentProcessID", wintypes.DWORD),
                ("pcPriClassBase", ctypes.c_long),
                ("dwFlags", wintypes.DWORD),
                ("szExeFile", ctypes.c_char * 260)]


def enum_procs():
    """[(name_lower, pid)] via Toolhelp -- no driver involvement."""
    k32 = ctypes.windll.kernel32
    k32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    k32.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
    k32.Process32First.restype = wintypes.BOOL
    k32.Process32First.argtypes = [wintypes.HANDLE, ctypes.POINTER(PENTRY)]
    k32.Process32Next.restype = wintypes.BOOL
    k32.Process32Next.argtypes = [wintypes.HANDLE, ctypes.POINTER(PENTRY)]
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    out = []
    try:
        e = PENTRY(); e.dwSize = ctypes.sizeof(PENTRY)
        ok = k32.Process32First(snap, ctypes.byref(e))
        while ok:
            out.append((e.szExeFile.decode(errors="replace").lower(),
                        e.th32ProcessID))
            ok = k32.Process32Next(snap, ctypes.byref(e))
    finally:
        k32.CloseHandle(snap)
    return out

def walk(dtb, va, g, st):
    """Bounded 4-level walk -> (leaf|None, note)."""
    t = dtb & 0xFFFFFFFFFF000
    path = []
    for sh in (39, 30, 21):
        pa = t + ((va >> sh) & 0x1FF) * 8
        if not g.is_ram(pa):
            return None, "guard-refused lvl%d" % sh
        try:
            e4 = struct.unpack("<Q", g.read_phys(pa, 8))[0]
            st["ok"] += 1
        except OSError as e:
            st["faults"] += 1
            st["last"] = "%s@%#x" % (str(e)[:60], pa)
            return None, "fault lvl%d" % sh
        path.append("%016X" % e4)
        if not (e4 & 1):
            return None, "absent lvl%d" % sh
        if (e4 & 0x80) and sh == 21:
            return (e4 & 0xFFFFFFFFFF000) + (va & 0x1FFFFF), "ok(2M)"
        nxt = e4 & 0xFFFFFFFFFF000
        if nxt and not g.is_ram(nxt):
            return None, "guard-refused child"
        t = nxt
    return t + (va & 0xFFF), "ok"


def main():
    t0 = time.time()
    say("h413 start %s py=%s" % (time.strftime("%F %T"), sys.version.split()[0]))
    try:
        g = gio.Gio(chunk=0x40000)
    except OSError as e:
        say("gio open failed: %s" % e)
        say("VERDICT: TRANSPORT_DOWN")
        return 2
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    ram = VA.Ram(ranges)
    g.is_ram = ram.page_ok
    say("ram map: %s (%d ranges)" % (note, len(ranges)))

    live = dict(enum_procs())
    targets = []
    for nm in PREF:
        for pid in [p for (n, p) in live.items() if n == nm]:
            targets.append((nm, pid))
            break
    say("targets=%s" % ", ".join("%s(%d)" % t for t in targets) or "NONE")
    if not targets:
        say("VERDICT: NO_TARGETS_ALIVE")
        return 3

    st = {"ok": 0, "faults": 0, "last": ""}
    sane = None
    carved = 0
    for nm, pid in targets:
        if pid == 22908:                       # keep the game out of the lane
            continue
        peb = VA._peb_va(pid)
        if not peb:
            say("[%s %d] no PEB via NtQuery (skipping)" % (nm, pid))
            continue
        dl.NAME = (nm.encode() + b"\x00").ljust(16, b"\x00")[:15] + b"\x00"
        hits_carved = 0
        for lo, hi in ((0x400000000, 0x800000000), (0x1000, 0x400000000)):
            band = [(max(l0, lo), min(h0, hi)) for l0, h0 in ranges
                    if h0 > lo and l0 < hi]
            if not band:
                continue
            t1 = time.time()
            try:
                hits, sk, ch, resc = dl.name_hits(g, band)
            except Exception as e:             # noqa: BLE001
                say("[%s %d] name_hits EXC %s" % (nm, pid, str(e)[:60]))
                continue
            say("[%s %d] band %#x-%#x hits=%d sk=%d (%.0fs)"
                % (nm, pid, lo, hi, len(hits), sk, time.time() - t1))
            hits_carved = len(hits)
            if hits:
                break
        if not hits_carved:
            say("[%s %d] carve zero in both bands" % (nm, pid))
            continue
        carved += 1
        good = None
        for hit in hits[:12]:
            for d in (0x338,) + tuple(range(0x300, 0x380, 8)) + (0x450, 0x4C8, 0x5A0):
                base = hit - d
                if base < 0x10000:
                    continue
                try:
                    if g.read_phys(base, 1)[0] != 3:
                        continue
                    dtb = struct.unpack("<Q", g.read_phys(base + 0x28, 8))[0]
                    prio = g.read_phys(base + 0x347, 1)[0]
                except OSError:
                    continue
                if not (0x1000 <= dtb < g.ram_top) or (dtb & 0xFFF):
                    continue
                if prio > 60:
                    continue
                leaf, na = walk(dtb, peb, g, st)
                if not leaf:
                    continue
                try:
                    ib = struct.unpack("<Q", g.read_phys(leaf + 0x10, 8))[0]
                    st["ok"] += 1
                except OSError:
                    continue
                if not (0x10000 < ib < 0x7FFFFFFFFFFF):
                    continue
                bleaf, nb = walk(dtb, ib, g, st)
                if not bleaf:
                    continue
                try:
                    mz = g.read_phys(bleaf, 2)
                    st["ok"] += 1
                except OSError:
                    continue
                say("[%s %d] CAND base=%#x dtb=%#x prio=%d ib=%#x mz=%r"
                    % (nm, pid, base, dtb, prio, ib, mz))
                if mz == b"MZ":
                    good = (base, dtb, ib)
                    break
            if good:
                break
        if good:
            sane = (nm, pid) + good
            say("[OK] %s(%d) dtb=%#x ib=%#x EPROCESS=%#x -> LIVE IMAGE CONFIRMED"
                % (nm, pid, good[1], good[2], good[0]))
            break
    say("--- carved=%d targets, ok_reads=%d faults=%d last=%s (%.0fs)"
        % (carved, st["ok"], st["faults"], st["last"] or "-", time.time() - t0))
    if sane:
        say("LIVE_MZ %s(%d)" % (sane[0], sane[1]))
        say("VERDICT: MACHINERY_SANE")
        return 0
    if carved:
        say("VERDICT: DAMAGED")
        return 4
    say("VERDICT: CARVE_ZERO")
    return 3


if __name__ == "__main__":
    try:
        rc = main()
    except Exception as e:                               # noqa: BLE001
        import traceback
        say("EXC %r" % e)
        say(traceback.format_exc())
        rc = 9
    say("h413 end rc=%d" % rc)
    sys.exit(rc)

