# -*- coding: utf-8 -*-
r"""h414_live_walk_forensic.py -- why did h413 report DAMAGED with ok=0?

One variable over h413: candidate visibility.  h413 cropped hits[:12], gated
silently, and printed nothing until a full journey; its 184 s == carve sum and
ok=0 faults=0 say every candidate died before the first walk read.  h414 merges
the PROVEN _qk_dtb14 lane (full hit list, byte-stepped ladder, UniqueProcessId
hunt, per-candidate traces) with h413's live-target framing + verdict taxonomy,
and adds: per-phase timers, gate-reason census, walk-note census, and an
EPROCESS-field PEB (base+0x2E0) as a second PEB source independent of handles.

  MACHINERY_SANE   >=1 live target walked to MZ (+ PE signature spot-check)
  LIVE_PARTIAL     objects walked and pages translated, zero MZ found
  DAMAGED          objects carved, zero walk progress on any of them
  CARVE_ZERO       no EPROCESS-class object surfaced anywhere
  TRANSPORT_DOWN   gio unusable from this shell

Read-only throughout.  R10: every physical read checked against usable ranges.
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

OUT = os.path.join(HERE, "h414_live_walk_forensic.txt")

T_GLOBAL_BUDGET = 480.0          # s; entire run
T_TARGET_SLICE = 150.0           # s; per-target candidate phase


def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(str(s) + "\n")


TH32CS_SNAPPROCESS = 0x2


class PENTRY(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD),
                ("th32ProcessID", wt.DWORD),
                ("th32DefaultHeap", ctypes.c_size_t),   # ULONG_PTR x64
                ("th32ModuleID", wt.DWORD),
                ("cntThreads", wt.DWORD),
                ("th32ParentProcessID", wt.DWORD),
                ("pcPriClassBase", ctypes.c_long),
                ("dwFlags", wt.DWORD),
                ("szExeFile", ctypes.c_char * 260)]


def enum_targets():
    """[(name_lower, pid)] for everyday EAAC-unprotected processes."""
    k32 = ctypes.windll.kernel32
    k32.CreateToolhelp32Snapshot.restype = wt.HANDLE
    k32.CreateToolhelp32Snapshot.argtypes = [wt.DWORD, wt.DWORD]
    k32.Process32First.restype = wt.BOOL
    k32.Process32First.argtypes = [wt.HANDLE, ctypes.POINTER(PENTRY)]
    k32.Process32Next.restype = wt.BOOL
    k32.Process32Next.argtypes = [wt.HANDLE, ctypes.POINTER(PENTRY)]
    pref = {"explorer.exe", "dwm.exe", "cmd.exe", "notepad.exe",
            "python.exe", "steam.exe", "msedgewebview2.exe", "svchost.exe"}
    out, seen = [], set()
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    try:
        e = PENTRY(); e.dwSize = ctypes.sizeof(PENTRY)
        ok = k32.Process32First(snap, ctypes.byref(e))
        while ok:
            nm = e.szExeFile.decode(errors="replace").lower()
            pid = int(e.th32ProcessID)
            if nm in pref and pid not in seen:
                out.append((nm, pid)); seen.add(pid)
            ok = k32.Process32Next(snap, ctypes.byref(e))
    finally:
        k32.CloseHandle(snap)
    return out


def peb_via_ntquery(pid):
    """PEBasic -> PEB VA or None; query-only handle, no VM_READ dependency."""
    class PEBasic(ctypes.Structure):
        _fields_ = [("status", ctypes.c_void_p), ("peb", ctypes.c_void_p),
                    ("affinity", ctypes.c_size_t), ("priority", ctypes.c_long),
                    ("uniqueid", ctypes.c_size_t), ("parent", ctypes.c_size_t)]
    k = ctypes.windll.kernel32
    nt = ctypes.windll.ntdll
    k.OpenProcess.argtypes = [wt.DWORD, wt.BOOL, wt.DWORD]
    k.OpenProcess.restype = ctypes.c_void_p
    nt.NtQueryInformationProcess.restype = ctypes.c_long
    nt.NtQueryInformationProcess.argtypes = [
        ctypes.c_void_p, wt.ULONG, ctypes.c_void_p,
        wt.ULONG, ctypes.POINTER(wt.ULONG)]
    h = k.OpenProcess(0x1000, False, pid)          # PROCESS_QUERY_LIMITED_INFO
    if not h:
        return None
    try:
        b = PEBasic()
        st = nt.NtQueryInformationProcess(
            ctypes.c_void_p(h), 0, ctypes.byref(b),
            ctypes.sizeof(b), None)
        return b.peb if st == 0 else None
    finally:
        k.CloseHandle(h)


def win_bytes(g, base, need=0x650):
    """Return >=need bytes anchored at base (page-window reads; None on fault)."""
    buf = bytearray()
    try:
        page = base & ~0xFFF
        buf.extend(g.read_phys(page, 0x1000))
        if (base & 0xFFF) + need > 0x1000:
            buf.extend(g.read_phys(page + 0x1000, 0x1000))
    except OSError:
        return None
    off = base & 0xFFF
    if len(buf) < off + need:
        return None
    return bytes(buf[off:off + need])


def walk(g, dtb, va, st, note_hook=None):
    """Bounded 4-level walk -> (leaf|None, note).  Counts every hop."""
    t = dtb & 0xFFFFFFFFFF000
    for sh in (39, 30, 21):
        pa = t + ((va >> sh) & 0x1FF) * 8
        if not g.is_ram(pa):
            st["geo_skip"] += 1
            return None, "geo lvl%d" % sh
        try:
            e4 = struct.unpack("<Q", g.read_phys(pa, 8))[0]
            st["ok"] += 1
        except OSError as ex:
            st["faults"] += 1
            st["last"] = "%s@%#x" % (str(ex)[:60], pa)
            return None, "fault lvl%d" % sh
        if not (e4 & 1):
            st["present_miss"] += 1
            return None, "np lvl%d" % sh
        if (e4 & 0x80) and sh == 21:               # 2 MiB leaf
            return (e4 & 0xFFFFFFFFFF000) + (va & 0x1FFFFF), "2M"
        t = e4 & 0xFFFFFFFFFF000
    st["depth4"] += 1
    return t + (va & 0xFFF), "ok"


def main():
    t0 = time.time()
    open(OUT, "w", encoding="utf-8").close()
    say("h414 start %s py=%s" % (time.strftime("%Y-%m-%d %H:%M:%S"),
                                 sys.version.split()[0]))
    try:
        g = gio.Gio(chunk=0x10000)
        _ = g.read_phys(0x1000, 8)                # smoke test
    except Exception as e:                        # noqa: BLE001
        say("transport unusable: %r" % e)
        say("VERDICT: TRANSPORT_DOWN")
        return 5
    ranges, _note = dl.usable_ranges(g.ram_top, None, None)
    ram = VA.Ram(ranges)
    g.is_ram = ram.page_ok
    say("ram map: %d ranges (map=%d bad=%d)"
        % (len(ranges), sum(a < b for a, b in ranges),
           sum(b < a for a, b in ranges)))

    targets = enum_targets()
    say("targets=%s" % (", ".join("%s(%d)" % (n, p) for n, p in targets)))
    if not targets:
        say("VERDICT: CARVE_ZERO")
        return 3

    st = collections.Counter(ok=0, faults=0, geo_skip=0, present_miss=0,
                             depth4=0)
    gates = collections.Counter()
    wnotes = collections.Counter()
    walk_attempts = 0
    sane = None
    deadline = t0 + T_GLOBAL_BUDGET

    for nm, pid in targets:
        if time.time() > deadline:
            say("[budget] global deadline hit; stopping target loop")
            break
        tg = collections.Counter()
        dl.NAME = (nm.encode() + b"\x00").ljust(16, b"\x00")[:15] + b"\x00"
        peb_nt = peb_via_ntquery(pid)
        say("[%s %d] peb_nt=%#x" % (nm, pid, peb_nt or 0))

        tc0 = time.time()                          # carve phase
        hits = []
        for lo, hi in ((0x400000000, 0x800000000), (0x1000, 0x400000000)):
            band = [(max(l0, lo), min(h0, hi)) for l0, h0 in ranges
                    if h0 > lo and l0 < hi]
            if not band:
                continue
            try:
                bh, sk, ch, resc = dl.name_hits(g, band)
            except Exception as e:                # noqa: BLE001
                say("[%s %d] name_hits EXC %s" % (nm, pid, str(e)[:60]))
                continue
            hits.extend(bh)
            say("[%s %d] band %#x-%#x hits=%d sk=%d (%.0fs)"
                % (nm, pid, lo, hi, len(bh), sk, time.time() - tc0))
            if bh:
                break
        if not hits:
            tg["no_hits"] += 1
            say("[%s %d] carve zero" % (nm, pid))
            gates.update(tg)
            continue
        say("[%s %d] probing %d hits (NO crop)" % (nm, pid, len(hits)))

        tcand0 = time.time()                       # candidate phase
        tgt_deadline = time.time() + T_TARGET_SLICE
        for hi_idx, hit in enumerate(hits):
            if time.time() > tgt_deadline or time.time() > deadline:
                say("[%s %d] time budget: stopped at hit %d/%d"
                    % (nm, pid, hi_idx, len(hits)))
                break
            for d in range(0x300, 0x380):          # byte ladder, dtb14-style
                base = hit - d
                if base < 0x10000:
                    continue
                buf = win_bytes(g, base, need=0x650)
                if buf is None:
                    gates["win_fault"] += 1; tg["win_fault"] += 1
                    continue
                if buf[0] != 3:
                    gates["type_not3"] += 1; tg["type_not3"] += 1
                    continue
                prio = buf[0x347]
                dtb = struct.unpack_from("<Q", buf, 0x28)[0]
                tok_hi = struct.unpack_from("<Q", buf, 0x248)[0] >> 48
                peb_fld = struct.unpack_from("<Q", buf, 0x2E0)[0]
                gates["type3_seen"] += 1; tg["type3_seen"] += 1
                if prio > 60:
                    gates["prio_out"] += 1; tg["prio_out"] += 1
                    continue
                if not (0x1000 <= dtb < g.ram_top) or (dtb & 0xFFF):
                    gates["dtb_out"] += 1; tg["dtb_out"] += 1
                    continue
                pido = None                        # UniqueProcessId hunt
                for off in range(0x100, 0x640, 4):
                    v = struct.unpack_from("<Q", buf, off)[0]
                    if v == pid or (v & 0xFFFFFFFF) == pid:
                        pido = off
                        break
                gates["obj_passed"] += 1; tg["obj_passed"] += 1
                say("[%s %d] OBJ hit=%#x d=%#x base=%#x dtb=%#x prio=%d "
                    "tokhi=%X pebfld=%#x pid@%s"
                    % (nm, pid, hit, d, base, dtb, prio, tok_hi, peb_fld,
                       ("%#x" % pido) if pido is not None else "none"))
                if pido is None and tok_hi != 0xFFFF:
                    gates["obj_unconfirmed"] += 1; tg["obj_unconfirmed"] += 1
                    continue
                peb = peb_fld if (0x1000 < peb_fld < 0x800000000000
                                  and not peb_fld & 7) else 0
                pebsrc = "field"
                if not peb and peb_nt:
                    peb, pebsrc = peb_nt, "ntq"
                elif peb and peb_nt and peb != peb_nt:
                    say("[%s %d]   PEB diverge field=%#x ntq=%#x (use %s)"
                        % (nm, pid, peb_fld, peb_nt, pebsrc))
                if not peb:
                    gates["no_peb"] += 1; tg["no_peb"] += 1
                    continue
                walk_attempts += 1
                leaf, note = walk(g, dtb, peb, st)
                wnotes["peb:" + note] += 1
                if not leaf:
                    gates["walk_peb"] += 1; tg["walk_peb"] += 1
                    continue
                try:
                    ib = struct.unpack("<Q", g.read_phys(leaf + 0x10, 8))[0]
                    st["ok"] += 1
                except OSError:
                    gates["ib_fault"] += 1; tg["ib_fault"] += 1
                    continue
                if not (0x10000 < ib < 0x7FFFFFFFFFFF):
                    gates["ib_range"] += 1; tg["ib_range"] += 1
                    continue
                walk_attempts += 1
                bleaf, bnote = walk(g, dtb, ib, st)
                wnotes["img:" + bnote] += 1
                if not bleaf:
                    gates["walk_img"] += 1; tg["walk_img"] += 1
                    continue
                try:
                    mz = g.read_phys(bleaf, 2)
                    lf = struct.unpack("<I", g.read_phys(bleaf + 0x3C, 4))[0]
                    pesig = g.read_phys(bleaf + lf, 4) \
                        if 0 < lf < 0x1000 else b""
                    st["ok"] += 2
                except OSError:
                    gates["mz_fault"] += 1; tg["mz_fault"] += 1
                    continue
                say("[%s %d]   IMG base=%#x leaf=%#x(%s) ib=%#x mz=%r pe=%r"
                    % (nm, pid, base, bleaf, bnote, ib, mz, pesig[:2]))
                gates["found_mz"] += 1; tg["found_mz"] += 1
                if mz == b"MZ" and not sane:
                    sane = (nm, pid, base, dtb, ib, peb, pebsrc)
                    if pesig[:2] == b"PE":
                        gates["found_pe"] += 1; tg["found_pe"] += 1
                    say("[OK] %s(%d) dtb=%#x ib=%#x EPROCESS=%#x "
                        "peb=%#x(%s) -> LIVE IMAGE CONFIRMED"
                        % (nm, pid, dtb, ib, base, peb, pebsrc))
            if sane:
                break
        gates.update(tg)
        say("[%s %d] phase carve=%.1fs cand=%.1fs gates=%s"
            % (nm, pid, tcand0 - tc0, time.time() - tcand0, dict(tg)))
        if sane:
            break

    say("--- objs_confirmed=%d walk_attempts=%d" % (gates["obj_passed"],
                                                    walk_attempts))
    say("--- reads: ok=%d faults=%d geo=%d np=%d depth4=%d last=%s"
        % (st["ok"], st["faults"], st["geo_skip"], st["present_miss"],
           st["depth4"], st["last"] or "-"))
    say("--- gates: %s" % dict(sorted(gates.items(), key=lambda kv: -kv[1])))
    say("--- notes: %s" % dict(sorted(wnotes.items(), key=lambda kv: -kv[1])))
    say("--- elapsed %.1fs" % (time.time() - t0))
    if sane:
        say("LIVE_MZ %s(%d)" % (sane[0], sane[1]))
        say("VERDICT: MACHINERY_SANE")
        return 0
    if walk_attempts:
        say("VERDICT: LIVE_PARTIAL")
        return 6
    if gates["type3_seen"]:
        say("VERDICT: DAMAGED")
        return 4
    say("VERDICT: CARVE_ZERO")
    return 3


if __name__ == "__main__":
    try:
        rc = main()
    except Exception as e:                        # noqa: BLE001
        import traceback
        say("EXC %r" % e)
        say(traceback.format_exc())
        rc = 9
    say("h414 end rc=%d" % rc)
    sys.exit(rc)
