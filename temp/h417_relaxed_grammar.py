# -*- coding: utf-8 -*-
r"""h417_relaxed_grammar.py -- is EPROCESS Type really 3 on 26200 tonight?

h414/416: quarter-million gate probes, ZERO survivors of type3+prio+dtb.
Two live hypotheses:
  DRIFT   real bodies exist but their Type byte isn't 3 this build
  SKIP    real name-pages fall in name_hits' skipped/faulted chunks
Cheap test for DRIFT: one carve, relax the Type gate, score windows by
JOINT FIELD GRAMMAR instead --
  pid_match   qword == pid (or low dword) in +0x1D0/+0x240/+0x2E8 area
  peb_sane    u64@0x2E0 in-user-range 8-aligned
  tok_canon   u64@0x248 >>48 == 0xFFFF
  dtb_sane    u64@0x28 ram-bounded page-aligned
Print every window with >=2 fields lit, plus the Type-byte census so the
DRIFT/SKIP separation is quantitative.

Read-only; R10 guard honoured via g.is_ram override.
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

OUT = os.path.join(HERE, "h417_relaxed_grammar.txt")
WIN_NEED = 0x650


def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(str(s) + "\n")

def one_target(g, ranges, nm, pid):
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
        winners, typebytes = [], collections.Counter()
        for hit in hits:
            for d in range(0x300, 0x380):
                base = hit - d
                if base < 0x10000:
                    continue
                try:
                    page = base & ~0xFFF
                    buf = g.read_phys(page, 0x1000)
                    if (base & 0xFFF) + WIN_NEED > 0x1000:
                        buf += g.read_phys(page + 0x1000, 0x1000)
                except OSError:
                    continue
                off = base & 0xFFF
                if len(buf) < off + WIN_NEED:
                    continue
                w = bytes(buf[off:off + WIN_NEED])
                tb = w[0]
                typebytes[tb] += 1
                dtb = struct.unpack_from("<Q", w, 0x28)[0]
                peb = struct.unpack_from("<Q", w, 0x2E0)[0]
                tok = struct.unpack_from("<Q", w, 0x248)[0] >> 48
                f_dtb = 0x1000 <= dtb < g.ram_top and not dtb & 0xFFF
                f_peb = 0x1000 < peb < 0x800000000000 and not peb & 7
                f_tok = tok == 0xFFFF
                f_pid = any(
                    struct.unpack_from("<Q", w, o)[0] == pid
                    or struct.unpack_from("<Q", w, o)[0] & 0xFFFFFFFF == pid
                    for o in (0x1D0, 0x240, 0x2E8))
                lit = sum((f_dtb, f_peb, f_tok, f_pid))
                if lit >= 2:
                    winners.append((lit, hit, d, base, tb, f_pid, dtb))
        say("[%s %d] typebyte census: %s"
            % (nm, pid, dict(typebytes.most_common(6))))
        for lit, hit, d, base, tb, fp, dtb in sorted(winners, reverse=True):
            say("[%s %d] WIN lit=%d hit=%#x d=%#x base=%#x type=%d "
                "pid=%s dtb=%#x" % (nm, pid, lit, hit, d, base, tb, fp, dtb))
        return winners
    return []

def main():
    t0 = time.time()
    open(OUT, "w", encoding="utf-8").close()
    say("h417 start %s py=%s" % (time.strftime("%Y-%m-%d %H:%M:%S"),
                                 sys.version.split()[0]))
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

    total = 0
    for nm, pid in want.items():
        if pid is None:
            continue
        total += len(one_target(g, ranges, nm, pid))
        if time.time() - t0 > 300:
            break

    say("--- winners=%d elapsed=%.1fs" % (total, time.time() - t0))
    if total:
        say("VERDICT: DRIFT_LIKELY (joint-grammar windows exist; check types)")
        return 0
    say("VERDICT: GRAMMAR_VOID (even relaxed grammar finds nothing)")
    return 3


if __name__ == "__main__":
    try:
        rc = main()
    except Exception as e:                        # noqa: BLE001
        import traceback
        say("EXC %r" % e)
        say(traceback.format_exc())
        rc = 9
    say("h417 end rc=%d" % rc)
    sys.exit(rc)
