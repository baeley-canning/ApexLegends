# -*- coding: utf-8 -*-
r"""h416_sticky_bisector.py -- is candidate-window unreadability STICKY?

After h414/415 exposed (a) decoy-dominated name-hit families and (b) win_fault
bursts that vary target to target, one question decides everything: for the
SAME physical page cluster, do repeat reads behave as

  STICKY       a given PA always refuses (structure/geology problem)
  TRANSIENT    a given PA intermittently refuses then heals (the documented
               gdrv3 1450-LAW, per-PFN sticky-then-heal)
  CLEAN        repeat reads are stable (tonight's failures were flukes)

Three co-localised probes per target make locality itself measurable:
  DISP   byte at candidate base (dispatcher type; tonight: mostly junk)
  DTBPML the candidate's own claimed DTB's first PML4 page (if sane)
  NAME   bytes back at the harvested name hit (POSITIVE CONTROL - reads fine
         tonight by construction, same neighbourhood as DISP)
Each probe is re-read N_REPEAT times at POLL_EVERY seconds; per-PA outcome
kept as an ok/fault ledger; final verdict names the regime per family.

Read-only throughout; R10 guard on every read.
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

OUT = os.path.join(HERE, "h416_sticky_bisector.txt")

N_REPEAT = 20
POLL_EVERY = 5.0                 # s between sweep rounds
TARGETS_MAX = 4                  # focus on ordered prefs
WINDOW_NEED = 0x650

def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(str(s) + "\n")


def enum_one_per_name(order):
    """[(name, pid)] first instance of each preferred name, pref-ordered."""
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
    rank = {n: i for i, n in enumerate(order)}
    first, seen = {}, set()
    snap = k32.CreateToolhelp32Snapshot(TH, 0)
    try:
        e = PE(); e.dwSize = ctypes.sizeof(PE)
        ok = k32.Process32First(snap, ctypes.byref(e))
        while ok:
            nm = e.szExeFile.decode(errors="replace").lower()
            if nm in rank and nm not in seen:
                first[nm] = int(e.th32ProcessID); seen.add(nm)
            ok = k32.Process32Next(snap, ctypes.byref(e))
    finally:
        k32.CloseHandle(snap)
    return sorted(first.items(), key=lambda kv: rank[kv[0]])


def find_candidates(g, ranges, nm, pid, cap_scored=3):
    """Carve + byte-ladder; return top cap_scored (base, dtb, hit) trios."""
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
        say("[%s %d] carve hits=%d" % (nm, pid, len(hits)))
        scored = []
        for hit in hits:
            for d in range(0x300, 0x380):
                base = hit - d
                if base < 0x10000:
                    continue
                try:
                    page = base & ~0xFFF
                    buf = g.read_phys(page, 0x1000)
                    if (base & 0xFFF) + WINDOW_NEED > 0x1000:
                        buf += g.read_phys(page + 0x1000, 0x1000)
                except OSError:
                    continue
                off = base & 0xFFF
                if len(buf) < off + WINDOW_NEED:
                    continue
                w = bytes(buf[off:off + WINDOW_NEED])
                if w[0] != 3:
                    continue
                dtb = struct.unpack_from("<Q", w, 0x28)[0]
                if not (0x1000 <= dtb < g.ram_top) or (dtb & 0xFFF):
                    continue
                if w[0x347] > 60:
                    continue
                scored.append((base, dtb, hit))
                if len(scored) >= cap_scored:
                    return scored
        return scored
    return []

def probe_family(g, pa, n_repeats, label):
    """Re-read a tiny field n times; return per-round ok-list + bytes seen."""
    ledger, vals = [], []
    for _ in range(n_repeats):
        try:
            b = g.read_phys(pa, 8)
            ledger.append(1); vals.append(b.hex()[:16])
        except OSError as ex:
            ledger.append(0); vals.append("ERR:%s" % str(ex)[:18])
    ok = sum(ledger)
    regime = ("CLEAN" if ok == n_repeats else
              "STICKY" if ok == 0 else "TRANSIENT")
    say("    [%s pa=%#x] %d/%d ok -> %s" % (label, pa, ok, n_repeats, regime))
    if regime != "CLEAN":
        say("      vals: %s" % " | ".join(vals[:8]))
    return regime, ok


def main():
    t0 = time.time()
    open(OUT, "w", encoding="utf-8").close()
    say("h416 start %s py=%s" % (time.strftime("%Y-%m-%d %H:%M:%S"),
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

    order = ["explorer.exe", "dwm.exe", "python.exe", "svchost.exe"]
    targets = enum_one_per_name(order)
    say("targets=%s" % (", ".join("%s(%d)" % t for t in targets)))

    regimes = collections.Counter()
    fam_detail = {}
    for nm, pid in targets[:TARGETS_MAX]:
        cands = find_candidates(g, ranges, nm, pid)
        if not cands:
            say("[%s %d] no type3+dualsane candidate -> no probe family"
                % (nm, pid))
            continue
        for ci, (base, dtb, hit) in enumerate(cands):
            fam = "%s(%d)#%d" % (nm, pid, ci)
            say("  FAMILY %s base=%#x dtb=%#x hit=%#x"
                % (fam, base, dtb, hit))
            r1, _o1 = probe_family(g, base, N_REPEAT, "DISP")
            r2, _o2 = probe_family(g, dtb & ~0xFFF, N_REPEAT, "DTBPML") \
                if (0x1000 <= dtb < g.ram_top and not dtb & 0xFFF) \
                else ("SKIP", 0)
            r3, _o3 = probe_family(g, hit, N_REPEAT, "NAME")
            for r in (r1, r2, r3):
                regimes[r] += 1
            fam_detail[fam] = dict(disp=r1, dtbpml=r2, name=r3)
        if time.time() - t0 > 420:
            say("[budget] stopping target loop early")
            break

    say("--- family regimes:")
    for fam, dd in fam_detail.items():
        say("    %-24s disp=%s dtbpml=%s name=%s"
            % (fam, dd["disp"], dd["dtbpml"], dd["name"]))
    say("--- regimes total: %s" % dict(regimes))
    say("--- elapsed %.1fs" % (time.time() - t0))

    clean = regimes["CLEAN"]; tr = regimes["TRANSIENT"]; stk = regimes["STICKY"]
    if tr > 0 and (stk or clean):
        say("VERDICT: LAW_TRANSIENT_MIXED (per-PFN sticky-then-heal live)")
        return 0
    if stk > 0 and tr == 0:
        say("VERDICT: STICKY_STRUCTURE (some PAs permanently unreadable)")
        return 7
    if clean > 0 and stk == 0 and tr == 0:
        say("VERDICT: ALL_CLEAN_TONIGHT_FLUKE")
        return 8
    say("VERDICT: NO_FAMILIES (no candidates survived static gates to probe)")
    return 3


if __name__ == "__main__":
    try:
        rc = main()
    except Exception as e:                        # noqa: BLE001
        import traceback
        say("EXC %r" % e)
        say(traceback.format_exc())
        rc = 9
    say("h416 end rc=%d" % rc)
    sys.exit(rc)
