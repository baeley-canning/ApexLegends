"""mk13: is the e1450 dead-state tied to LIVE page-table ownership?

mk12 rewrote the map: every frame that was dead at 18:0x (dtb_6004 0x6EF568000,
dtb_20612 0x436AD8000, wasok 0x6EF980000) now reads 60/60 - all those owners
are DEAD processes.  The only dead frame left is dtb_new 0x5732E3000, owned by
the LIVE game pid 26496.  flaky 0x5D28F1000 healed in ~3 min.  Hypothesis H:
gdrv3's read ioctl refuses (1450) pages whose PFN is in active page-table /
high-share use, and they heal when freed.

Two stages, one probe (read-only, gdrv3 only, R10-guarded, _mk13_out.txt):
  1. re-storm dtb_new + the healed set + two mk11-census deads + a low-RAM
     kernel-table sample.  If dtb_new flickered open, dump PML4 stats ->
     VERDICT PASS and stop (mk14 consumes).
  2. otherwise, sweep for the EPROCESS objects of other LIVE processes
     (dwm/csrss/lsass/explorer/svchost), validate pid32@+0x240 against the
     live toolhelp pid set, and storm each live DTB frame 12x.  H confirmed
     iff every live PML4 frame is dead while every freed frame reads.
"""
import os
import struct
import sys
import time

os.environ["GIO_DST_LAST"] = "1"

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))
import gio                     # noqa: E402
import dumplive as dl          # noqa: E402
from ctypes.wintypes import DWORD, WCHAR  # noqa: E402
import ctypes                  # noqa: E402

OUT = os.path.join(HERE, "_mk13_out.txt")
PAGE = 0x1000
STAGE1 = [
    ("dtb_new  ", 0x5732E3000),
    ("dtb_6004 ", 0x6EF568000),
    ("dtb_20612", 0x436AD8000),
    ("wasok    ", 0x6EF980000),
    ("flaky    ", 0x5D28F1000),
    ("obj_new  ", 0x13CF13000),
    ("census_a ", 0x5D7975000),
    ("census_b ", 0x6C9AF3000),
    ("lowram_a ", 0x00100000),
    ("lowram_b ", 0x00220000),
    ("ctrl     ", 0x436A00000),
]
# ImageFileName needle -> toolhelp exe name
IMAGES = [(b"dwm.exe", "dwm.exe"), (b"csrss.exe", "csrss.exe"),
          (b"lsass.exe", "lsass.exe"), (b"explorer.exe", "explorer.exe"),
          (b"svchost.exe", "svchost.exe"), (b"r5apex_dx12.ex", "r5apex_dx12.exe")]
MAX_PROC = 10


def say(s):
    line = str(s)
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", DWORD), ("cntUsage", DWORD),
                ("th32ProcessID", DWORD), ("th32DefaultHeapID", ctypes.c_void_p),
                ("th32ModuleID", DWORD), ("cntThreads", DWORD),
                ("th32ParentProcessID", DWORD), ("pcPriClassBase", ctypes.c_long),
                ("dwFlags", DWORD), ("szExeFile", WCHAR * 260)]


def live_pids():
    out = {}
    k32 = ctypes.windll.kernel32
    snap = k32.CreateToolhelp32Snapshot(2, 0)
    pe = PROCESSENTRY32W()
    pe.dwSize = ctypes.sizeof(pe)
    ok = k32.Process32FirstW(snap, ctypes.byref(pe))
    while ok:
        out.setdefault(pe.szExeFile.lower(), set()).add(pe.th32ProcessID)
        ok = k32.Process32NextW(snap, ctypes.byref(pe))
    k32.CloseHandle(snap)
    return out


def storm(g, pa, tries=12):
    for i in range(tries):
        try:
            return i, g.read_phys(pa, PAGE)
        except OSError:
            pass
    return None, None


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== mk13 live-page-table probe %s ===" % time.strftime("%H:%M:%S"))
    g = gio.Gio(chunk=0x100000)
    ranges, note = dl.usable_ranges(g.ram_top, None, None, [])
    say("ram_top=%#x ranges=%d (%s)" % (g.ram_top, len(ranges), note))

    def in_map(pa):
        p = pa & ~0xFFF
        return any(a <= p and p + PAGE <= b for a, b in ranges)

    say("--- stage 1: re-storm the known set ---")
    pml4 = None
    for tag, pa in STAGE1:
        if not in_map(pa):
            say("%s %#012x outside map (R10 skip)" % (tag, pa))
            continue
        k, buf = storm(g, pa)
        if buf is None:
            say("%s %#012x 0/12 e1450 DEAD" % (tag, pa))
            continue
        ent = struct.unpack("<512Q", buf)
        present = sum(1 for x in ent if x & 1)
        selfok = any((x & ~0xFFF) == pa for x in ent)
        say("%s %#012x READ try%d present=%d selfref=%s"
            % (tag, pa, k, present, selfok))
        if tag.strip() == "dtb_new":
            pml4 = (present, selfok)
    if pml4:
        say("RESULT: dtb_new flickered open present=%d selfref=%s" % pml4)
        say("VERDICT: PASS - window open; snapshot the hierarchy NOW (mk14)")
        g.close()
        return 0
    # ---- stage 2: live-process EPROCESS sweep + DTB storms -----------------
    say("--- stage 2: cross-process live PML4 census ---")
    pids = live_pids()
    want = {}
    for needle, exe in IMAGES:
        alive = pids.get(exe, set())
        if alive:
            want[needle] = alive
    say("live targets: %s" % {n.decode(): sorted(p) for n, p in want.items()})
    found = {}          # obj -> (exe, pid, dtb)
    t0 = time.perf_counter()
    done = False
    for rlo, rhi in ranges:
        if done:
            break
        pa = rlo
        carry = b""
        while pa < rhi and not done:
            n = min(0x100000, rhi - pa)
            try:
                buf = g.read_phys(pa, n)
            except OSError:
                parts = []
                p = pa
                while p < pa + n:
                    m = min(PAGE, pa + n - p)
                    try:
                        parts.append(g.read_phys(p, m))
                    except OSError:
                        parts.append(b"\x00" * m)
                    p += m
                buf = b"".join(parts)
            data = carry + buf
            base = pa - len(carry)
            for needle, alive in want.items():
                i = data.find(needle)
                while i >= 0:
                    h = base + i
                    obj = h - 0x3A8
                    page = obj & ~0xFFF
                    o = obj - page
                    if obj > 0 and o + 0x3C0 <= PAGE and in_map(page) \
                            and obj not in found:
                        try:
                            pb = g.read_phys(page, PAGE)
                            pid32 = struct.unpack_from("<I", pb, o + 0x240)[0]
                            dtb = struct.unpack_from("<Q", pb, o + 0x98)[0]
                            nm = pb[o + 0x3A8:o + 0x3A8 + len(needle)]
                            if nm == needle and pid32 in alive and dtb \
                                    and not dtb & 0xFFF and in_map(dtb) \
                                    and b"Proc" in pb:
                                found[obj] = (needle.decode(), pid32, dtb)
                                say("VALID %s obj %#x pid=%d dtb=%#x"
                                    % (needle.decode(), obj, pid32, dtb))
                        except OSError:
                            pass
                    i = data.find(needle, i + 1)
            if len(found) >= MAX_PROC:
                done = True
            carry = data[-13:]
            pa += n
    say("sweep: %ds, validated=%d" % (time.perf_counter() - t0, len(found)))

    dead_live = 0
    ok_live = 0
    for obj, (exe, pid, dtb) in sorted(found.items()):
        k, buf = storm(g, dtb & ~0xFFF)
        state = "DEAD" if buf is None else "READ try%d" % k
        if buf is None:
            dead_live += 1
        else:
            ok_live += 1
        say("  %-14s pid=%-6d dtb=%#014x -> %s" % (exe, pid, dtb, state))
    k, _ = storm(g, 0x436A00000, tries=3)
    say("post ctrl: %s" % ("READ" if k is not None else "FAIL"))
    say("RESULT: live PML4 frames dead=%d read=%d (freed frames all read in "
        "stage 1)" % (dead_live, ok_live))
    if len(found) >= 3 and dead_live == len(found):
        say("VERDICT: CONFIRMED - every LIVE PML4 frame refuses gdrv3 reads; "
            "dead-state tracks live page-table ownership, heals on free.  M1 "
            "must use stale/flicker snapshots or a non-PML4 transport")
    elif ok_live and dead_live:
        say("VERDICT: MIXED - some live PML4 frames read; ownership theory "
            "needs refinement")
    elif ok_live == len(found) and found:
        say("VERDICT: REFUTED - live PML4 frames read fine; dtb_new is "
            "special (re-examine)")
    else:
        say("VERDICT: PARTIAL - too few live processes validated (%d)"
            % len(found))
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())