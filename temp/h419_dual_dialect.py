# -*- coding: utf-8 -*-
r"""h419_dual_dialect.py -- which EPROCESS offset layout is REAL tonight?

Tribe memory holds two verified-but-conflicting dialects:
  A (11/07 era, _qk_dtb14..h41x): name@+0x338, dtb@+0x28, prio@+0x347, pid@0x1D0
  B (mk11, 08/11, verdict-graded): name@+0x3A8, dtb@+0x98, pid@+0x240, 'Proc' tag
If tonight's boot speaks dialect B, every A-dialect candidate base sat 0x70
behind the true object and read junk -- exactly the observed zero-survivor
wash-out.  One carve per target; BOTH dialects scored on every hit; per-dialect
survivors, type-byte census AT the dialect-implied base, and header previews.

Read-only; R10 honoured.
"""
import collections
import ctypes
import ctypes.wintypes as wt
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
EXT = os.path.join(ROOT, "ext")
sys.path.insert(0, EXT)
import gio                       # noqa: E402
import dumplive as dl            # noqa: E402
import qk_va as VA               # noqa: E402

OUT = os.path.join(HERE, "h419_dual_dialect.txt")

DIALECTS = {
    "A338": dict(name=0x338, dtb=0x28, prio=0x347, pids=(0x1D0, 0x240)),
    "B3A8": dict(name=0x3A8, dtb=0x98, prio=0x3B7, pids=(0x240, 0x1D0)),
}


def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(str(s) + "\n")


def score_window(g, base, dia, pid, need):
    """Return (lit, info-dict) at dialect-implied base."""
    try:
        page = base & ~0xFFF
        buf = g.read_phys(page, 0x1000)
        if (base & 0xFFF) + need > 0x1000:
            buf += g.read_phys(page + 0x1000, 0x1000)
    except OSError:
        return None
    off = base & 0xFFF
    if len(buf) < off + need:
        return None
    w = bytes(buf[off:off + need])
    tb = w[0]
    prio = w[dia["prio"]]
    dtb = struct.unpack_from("<Q", w, dia["dtb"])[0]
    f_dtb = 0x1000 <= dtb < g.ram_top and not dtb & 0xFFF
    f_prio = prio <= 60
    f_typ = tb == 3
    f_pid = any(struct.unpack_from("<Q", w, o)[0] == pid
                or struct.unpack_from("<Q", w, o)[0] & 0xFFFFFFFF == pid
                for o in dia["pids"])
    lit = f_typ + f_prio + f_dtb + f_pid
    return dict(lit=lit, typ=tb, prio=prio, dtb=dtb, f_pid=f_pid,
                f_dtb=f_dtb, f_prio=f_prio, f_typ=f_typ)


def one_target(g, ranges, nm, pid, need=0x430):
    dl.NAME = (nm.encode() + b"\x00").ljust(16, b"\x00")[:15] + b"\x00"
    for lo, hi in ((0x400000000, 0x800000000), (0x1000, 0x400000000)):
        band = [(max(l0, lo), min(h0, hi)) for l0, h0 in ranges
                if h0 > lo and l0 < hi]
        if not band:
            continue
        try:
            hits, sk, ch, resc = dl.name_hits(g, band)
        except Exception:                          # noqa: BLE001
            continue
        if not hits:
            continue
        say("[%s %d] hits=%d" % (nm, pid, len(hits)))
        tally = {dn: dict(winners=[], types=collections.Counter())
                 for dn in DIALECTS}
        for hit in hits:
            for dn, dia in DIALECTS.items():
                base = hit - dia["name"]
                if base < 0x10000:
                    continue
                sc = score_window(g, base, dia, pid, need)
                if sc is None:
                    continue
                tally[dn]["types"][sc["typ"]] += 1
                if sc["lit"] >= 3 or (sc["lit"] >= 2 and sc["f_pid"]
                                      and sc["f_dtb"]):
                    tally[dn]["winners"].append((hit, sc["lit"], sc))
        for dn in ("A338", "B3A8"):
            tw, tt = tally[dn]["winners"], tally[dn]["types"]
            top = dict(tt.most_common(5))
            say("[%s %d] dialect %s: winners=%d typecensus(top5)=%s"
                % (nm, pid, dn, len(tw), top))
            for hit, lit, sc in tw[:6]:
                say("    %s WIN hit=%#x base=%#x lit=%d typ=%d prio=%d "
                    "dtb=%#x pid=%s"
                    % (dn, hit, hit - DIALECTS[dn]["name"], lit,
                       sc["typ"], sc["prio"], sc["dtb"], sc["f_pid"]))
        return tally
    return None


def main():
    t0 = time.time()
    open(OUT, "w", encoding="utf-8").close()
    say("h419 start %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
    try:
        g = gio.Gio(chunk=0x10000)
        _ = g.read_phys(0x1000, 8)
    except Exception as e:                        # noqa: BLE001
        say("transport unusable: %r" % e)
        say("VERDICT: TRANSPORT_DOWN")
        return 5
    ranges, _n = dl.usable_ranges(g.ram_top, None, None)
    ram = VA.Ram(ranges)
    g.is_ram = ram.page_ok

    TH = 0x2

    class PE(ctypes.Structure):
        _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD),
                    ("th32ProcessID", wt.DWORD),
                    ("th32DefaultHeap", ctypes.c_size_t),
                    ("th32ModuleID", wt.DWORD), ("cntThreads", wt.DWORD),
                    ("th32ParentProcessID", wt.DWORD),
                    ("pcPriClassBase", ctypes.c_long),
                    ("dwFlags", wt.DWORD), ("szExeFile", ctypes.c_char * 260)]

    k32 = ctypes.windll.kernel32
    k32.CreateToolhelp32Snapshot.restype = wt.HANDLE
    k32.Process32First.restype = wt.BOOL
    k32.Process32First.argtypes = [wt.HANDLE, ctypes.POINTER(PE)]
    k32.Process32Next.restype = wt.BOOL
    k32.Process32Next.argtypes = [wt.HANDLE, ctypes.POINTER(PE)]
    want = {"explorer.exe": None, "dwm.exe": None}
    snap = k32.CreateToolhelp32Snapshot(TH, 0)
    try:
        e = PE(); e.dwSize = ctypes.sizeof(PE)
        ok = k32.Process32First(snap, ctypes.byref(e))
        while ok:
            nm = e.szExeFile.decode(errors="replace").lower()
            if nm in want and want[nm] is None:
                want[nm] = int(e.th32ProcessID)
            ok = k32.Process32Next(snap, ctypes.byref(e))
    finally:
        k32.CloseHandle(snap)

    grand = dict(A338=0, B3A8=0)
    for nm, pid in want.items():
        if pid is None:
            continue
        tal = one_target(g, ranges, nm, pid)
        if tal:
            for dn in grand:
                grand[dn] += len(tal[dn]["winners"])
        if time.time() - t0 > 240:
            break

    say("--- total winners A338=%d B3A8=%d elapsed=%.1fs"
        % (grand["A338"], grand["B3A8"], time.time() - t0))
    if grand["A338"] == 0 and grand["B3A8"] == 0:
        say("VERDICT: BOTH_DIALECTS_VOID (deeper surgery required)")
        return 3
    if grand["B3A8"] and not grand["A338"]:
        say("VERDICT: DIALECT_B_WINS (mk11 offsets; 0x338 recipes are stale)")
        return 2
    if grand["A338"] and not grand["B3A8"]:
        say("VERDICT: DIALECT_A_WINS (offsets fine; cause elsewhere)")
        return 1
    say("VERDICT: AMBIGUOUS (both lit; tighten and re-run)")
    return 4


if __name__ == "__main__":
    try:
        rc = main()
    except Exception as e:                        # noqa: BLE001
        import traceback
        say("EXC %r" % e)
        say(traceback.format_exc())
        rc = 9
    say("h419 end rc=%d" % rc)
    sys.exit(rc)
