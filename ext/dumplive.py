r"""dumplive.py -- dump the live r5apex_dx12 image through gdrv3 physical reads.

p40d (track A).  PURE READ probe: no driver load, no DSE write, no service
touch, no writable mapping -- everything goes through 0xC3502014, so there is
no pre-state to restore beyond closing the handle.

Method
  1. scan OS-declared usable RAM only (resource map `.Translated`, minus the
     BADPA ranges previous runs died on) for the pool copy of
     EPROCESS.ImageFileName == "r5apex_dx12.exe", gate the containing page on
     UniqueProcessId == pid at the 26200 offset (+0x1d0), verify the name at the
     derived base (+0x338), score the 26200 object shape, and read
     DirectoryTableBase (+0x28).  A chunk that faults is retried page by page.
  2. walk PML4[0] of that CR3 and take the first page that carries MZ + valid
     PE32+ headers and SizeOfImage > 64 MiB -- no other module in the process
     qualifies (r5apex_dx12.exe is ~700 MiB); the PTE index chain yields the
     image base VA
  3. copy headers and every present page of every section to temp\r5apex_live
     .bin, unmapped pages zero-filled (standard module dump)

Guards, because a bad PA read is a bugcheck
  * every table page and leaf page PA must pass is_ram() before it is read
  * a scan chunk that faults is skipped, never retried at random offsets
  * candidate CR3s are deduped, leaf probing is capped, PE validation is
    strict (Machine 0x8664, magic 0x20B, SectionAlignment 0x1000, sane
    table/header sizes) -- a random MZ byte does not become a dump base
"""
import ctypes
import hashlib
import os
import struct
import subprocess
import sys
import time
import winreg
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

ROOT = os.path.dirname(HERE)
# DUMP_OUT / DUMP_PROG let one probe number keep its own output file (R5) without
# forking the script; the defaults stay p40d so older recipes keep working.
OUT = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_OUT", "p40d_livedump.txt"))
PROG = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_PROG", "p40d_progress.txt"))
THROTTLE_MS = 0   # sleep THROTTLE_MS every 64 chunks in the sweeps: the 0x124 lesson -
                  # a full-speed 27 GB gdrv3 storm pushes a marginal IMC into a WHEA
                  # machine check (three identical 0x124 dumps at 03:46/03:50/03:54)
RETRY_MS = 50     # retry_phys backoff base; frame-try loops cut this to ~10 ms so a
                  # junk frame costs 0.3 s instead of 1.4 s across 200k candidates
NAME = b"r5apex_dx12.ex\x00"     # 14 chars + NUL: ImageFileName[15] keeps the
                                 # NUL, so 15 chars are stored truncated (p43x)
PROC_NAME = "r5apex_dx12"

SCAN_LO = 0x100000
SCAN_CHUNK = 0x10000            # ioctl dst is allocated for this; dump lowers it
# Hop budget: consecutive physical pages a walk may lose before it declares the
# device dead.  0x200000 is a *pinned* fault (p104: err 1450 on 3/3 tries, three
# separate runs, three different landing buffers, control read 0x100000 ok=1
# throughout) - it will never come back, so a walk must step over it instead of
# stalling.  Unbounded hopping is useless though: with the device gone every page
# faults and a 4 GiB scan would crawl.  64 pages = 256 KiB of fully dead map is
# far past one pin and far short of a dead device.
HOP_MAX = int(os.environ.get("GIO_HOP_MAX", "64"))
# Hop *stride* in pages, used only while a page is already lost: the p106w run
# crossed 0x10000000->0x1400f000 (64 MiB) without a single readable page, so the
# p104 "pinned" fault is not a pin, it is a contiguous pocket and a 1-page hop
# spends 16k faults to learn where it ends.  With stride N the walk probes every
# Nth page *until one reads*, then drops back to 1 page so the edge is exact and
# the good RAM behind it gets full coverage.  The fast path is SCAN_CHUNK (16
# pages) wide, so strides below 16 are indistinguishable from 1.
HOP_STRIDE = int(os.environ.get("GIO_HOP_STRIDE", "1"))
# Set by pid_scan when the hop budget trips: the device, not the address, is the
# suspect and the tail of the map was never read.
SCAN_STOPPED = False
# Last lost page and first page that read again -- the pocket's two edges, kept
# on the module because pid_scan's return tuple is already spoken for.
HOP_LAST = 0
FIRST_GOOD = 0
CKPT_BYTES = 0x10000000         # progress checkpoint every 256 MiB scanned
HOLES = [(0x000A0000, 0x00100000),      # VGA/ROM
         (0xC0000000, 0x100000000)]     # PCI/MMIO space
# OS-declared usable RAM.  A read of an address outside this map is the bugcheck
# vector (reserved/MMIO PA), so the map -- not HOLES -- is the primary truth.
RESMAP_KEY = r"HARDWARE\RESOURCEMAP\System Resources\Physical Memory"
BADPA_FILE = os.path.join(ROOT, "_ritual", "p38_badpa.txt")
# The 15-byte pattern also matches every NUL-terminated copy (p43u: 1200 hits
# in the first 14.5 GiB alone, so 1200 truncated the map at half).  The cap is
# only a runaway guard now; SCANEND says explicitly when it bites.
HIT_CAP = 20000
PTE_CAP = 6000000
# The scanned string is _EPROCESS.ImageFileName, which sits *inside* the object,
# so the EPROCESS base is BELOW the hit: signed deltas.
# p43x settled the storage: a 15-char name is written as 14 chars + NUL, so the
# pattern is 14 chars plus the NUL -- exactly the 15-byte field.  p43u's 15-char
# pattern (no NUL) and p43q's 16-byte one each missed the real object, one byte
# too many and one too few.  The PriorityClass byte at +0x347, right behind the
# NUL, is what still proves the hit is an object and not a string copy.
NAME = b"r5apex_dx12.ex\x00"              # 15 bytes, NUL included
OFF_NAME = 0x338                          # 26200 ImageFileName (was 0x4c8)
OFF_TOKEN = 0x248                         # _EPROCESS.Token (_EX_FAST_REF)
OFF_PEB = 0x2e0                           # _EPROCESS.ProcessEnvironmentBlock
PC_OFF = OFF_NAME + len(NAME)             # 0x347 PriorityClass: the 16th byte
NEED = 0x350                              # bytes needed from base to PC_OFF+1
# 26200: UniqueProcessId +0x1d0.  The pid window is still a window (+-0x30,
# step 4) so the DTB lane -- not the pid -- keeps being the verdict.
# p43x: the flink of all three real candidates ends on lane 0x258, not the
# 0x1d8 the symbol table gave, so 0x258 is the lane and 0x1d8 only scores.
NAME_DELTAS = range(-0x360, -0x310, 8)    # 0x338 +/- build drift
SHIFTS = NAME_DELTAS                      # legacy alias
PID_OFFS = range(0x1a0, 0x200, 4)         # 0x1d0 +/- 0x30
LINK_OFF = 0x258                          # ActiveProcessLinks flink (score only)
LINK_ALT = 0x1d8                          # symbol-table lane, scores lower
MIN_SCORE = 6                             # below this a "shape" is noise
PAGE = 0x1000                            # gio.PAGE is not imported; the 4 KiB
                                         # rescue and page arithmetic need it
PAGE_BACK = 0x1000                       # back page read: carries the base
MASK = 0x000FFFFFFFFFF000
MIN_IMAGE = 0x4000000
MAX_IMAGE = 0xC0000000

OPT = {"lo": None, "hi": None, "chunk": SCAN_CHUNK, "inplace": False,
       "ram_top": 0, "hex": False, "why": False}
# --inplace: run elevated_main() directly and never relaunch.  The staged
# C:\Windows\Temp wrapper already carries an elevated token, so a second
# ShellExecuteEx("runas") hop is pure failure surface (it cost a -1 exit and a
# 7 ms child lifetime on p40f).  --elevated keeps working as its alias.

LOG = []


def log(s):
    LOG.append(s)
    print(s)


def prog(s):
    """Append-only, flushed, one line.  The scan can hard-hang the box, so the
    progress file -- not the captured console -- is the only durable state."""
    try:
        with open(PROG, "a", encoding="utf-8") as f:
            f.write("%s  %s\n" % (time.strftime("%H:%M:%S"), s))
            f.flush()
            os.fsync(f.fileno())
    except OSError:
        pass


kernel32 = gio.kernel32
shell32 = ctypes.WinDLL("shell32", use_last_error=True)
advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)


# ---------------------------------------------------------------- elevation
# x64 ctypes truncates every un-annotated restype to c_int.  GetCurrentProcess()
# returned a sign-extended pseudo-handle and OpenProcessToken then failed, so this
# function always said "not elevated" -- that warning is what p40d printed while
# the token itself was fine.  Annotate, then gate on the call results.
kernel32.GetCurrentProcess.restype = wintypes.HANDLE
advapi32.OpenProcessToken.argtypes = [wintypes.HANDLE, wintypes.DWORD,
                                      ctypes.POINTER(wintypes.HANDLE)]
advapi32.OpenProcessToken.restype = wintypes.BOOL
advapi32.GetTokenInformation.argtypes = [wintypes.HANDLE, ctypes.c_int,
                                         ctypes.c_void_p, wintypes.DWORD,
                                         ctypes.POINTER(wintypes.DWORD)]
advapi32.GetTokenInformation.restype = wintypes.BOOL


def elevation():
    """1 when the current token is elevated, 0 otherwise."""
    tok = wintypes.HANDLE()
    if not advapi32.OpenProcessToken(kernel32.GetCurrentProcess(), 0x0008,
                                     ctypes.byref(tok)):
        return 0
    try:
        rl = wintypes.DWORD(0)
        if not advapi32.GetTokenInformation(tok, 20, ctypes.byref(rl), 4,
                                            ctypes.byref(rl)):
            return 0
        return rl.value
    finally:
        kernel32.CloseHandle(tok)


class SHELLEXECUTEINFOW(ctypes.Structure):
    # lpFile was missing here until 08/11: the struct came out 104 bytes, cbSize was
    # rejected and the API read lpVerb ("runas") as the file to launch, so every
    # ShellExecuteExW("runas") hop failed with err=5 and the elevated relaunch of the
    # producers never ran.  Field order and count are load-bearing: 112 bytes on x64.
    _fields_ = [("cbSize", wintypes.DWORD), ("fMask", wintypes.ULONG),
                ("hwnd", wintypes.HWND), ("lpVerb", wintypes.LPCWSTR),
                ("lpFile", wintypes.LPCWSTR),
                ("lpParameters", wintypes.LPCWSTR),
                ("lpDirectory", wintypes.LPCWSTR), ("nShow", ctypes.c_int),
                ("hInstApp", wintypes.HINSTANCE), ("lpIDList", wintypes.LPVOID),
                ("lpClass", wintypes.LPCWSTR), ("hkeyClass", wintypes.HKEY),
                ("dwHotKey", wintypes.DWORD), ("hIcon", wintypes.HANDLE),
                ("hProcess", wintypes.HANDLE)]


def run_elevated(params):
    sei = SHELLEXECUTEINFOW()
    sei.cbSize = ctypes.sizeof(sei)
    sei.fMask = 0x00000040
    sei.lpVerb = "runas"
    sei.lpFile = sys.executable
    sei.lpParameters = params
    sei.lpDirectory = HERE
    sei.nShow = 1
    if not shell32.ShellExecuteExW(ctypes.byref(sei)):
        return "ShellExecuteExW failed err=%d" % ctypes.get_last_error()
    kernel32.WaitForSingleObject(sei.hProcess, 600000)
    code = wintypes.DWORD(0)
    kernel32.GetExitCodeProcess(sei.hProcess, ctypes.byref(code))
    kernel32.CloseHandle(sei.hProcess)
    return "elevated child finished, exit=%d" % code.value


# ---------------------------------------------------------------- process id
class PROCESSENTRY32W(ctypes.Structure):
    _fields_ = [("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD),
                ("th32ProcessID", wintypes.DWORD),
                ("th32DefaultHeapID", ctypes.c_void_p),
                ("th32ModuleID", wintypes.DWORD), ("cntThreads", wintypes.DWORD),
                ("th32ParentProcessID", wintypes.DWORD),
                ("pcPriClassBase", ctypes.c_long), ("dwFlags", wintypes.DWORD),
                ("szExeFile", wintypes.WCHAR * 260)]


def find_pid():
    snap = kernel32.CreateToolhelp32Snapshot(0x00000002, 0)
    if snap == ctypes.c_void_p(-1).value:
        return None
    pe = PROCESSENTRY32W()
    pe.dwSize = ctypes.sizeof(pe)
    ok = kernel32.Process32FirstW(snap, ctypes.byref(pe))
    hit = None
    while ok:
        if pe.szExeFile.lower().startswith(PROC_NAME):
            hit = pe.th32ProcessID
            break
        ok = kernel32.Process32NextW(snap, ctypes.byref(pe))
    kernel32.CloseHandle(snap)
    return hit


# ---------------------------------------------------------------- ram scan
def load_bad(path=BADPA_FILE):
    """PA ranges that a previous run died on (p36/p38 durable breadcrumb).

    Blacklisting them lets a re-run walk past the page that bugchecks instead of
    dying on it again."""
    bad = []
    try:
        with open(path, encoding="utf-8") as f:
            for ln in f:
                ln = ln.strip()
                if "-" not in ln:
                    continue
                a, b = ln.split("-", 1)
                try:
                    lo, hi = int(a, 16), int(b, 16)
                except ValueError:
                    continue
                if hi > lo:
                    bad.append((lo, hi))
    except OSError:
        pass
    return bad


_BAD = None


def bad_intervals():
    """load_bad() read once per run (the file is durable and can be long)."""
    global _BAD
    if _BAD is None:
        _BAD = load_bad()
    return _BAD


def in_bad(pa, bad=None):
    """True if `pa` is in a PA range a previous run already lost.

    A pinned-fault page (p104: 0x200000, err 1450 three times over three runs and
    three landing buffers) reads exactly like a dead device from the per-page
    path.  The pin list is what tells the two apart, so the walker can hop over
    the hole without spending three retries on it or eating its hop budget.
    """
    for lo, hi in (bad_intervals() if bad is None else bad):
        if lo <= pa < hi:
            return True
    return False


def ram_map():
    """.Translated of the resource map -> [(lo, hi)] of OS-declared RAM.

    REG_RESOURCE_LIST is unreadable through .NET (p36 proved that the empty
    PowerShell parse silently degenerated the filter to "pa < ramTop").  Shape,
    verified byte-for-byte against `_ritual\\_ramhex.txt`: header 20 B
    (count, InterfaceType, BusNumber, Version, Revision, desc count), then 20 B
    descriptors type(1) share(1) flags(2) start(8) length(8); type 3 = Memory,
    type 7 = MemoryLarge where the length is shifted by the LARGE_xx flag.
    Returns (ranges, note); an empty list means "could not read"."""
    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, RESMAP_KEY, 0,
                            winreg.KEY_READ) as k:
            raw, _ = winreg.QueryValueEx(k, ".Translated")
    except OSError as e:
        return [], "open/query: %s" % e
    if not isinstance(raw, bytes) or len(raw) < 40:
        return [], "short value len=%d" % (len(raw) if raw else 0)
    count = min(struct.unpack_from("<I", raw, 16)[0], 64)
    out = []
    off = 20
    for _ in range(count):
        if off + 20 > len(raw):
            break
        t = raw[off]
        flags = struct.unpack_from("<H", raw, off + 2)[0]
        lo = struct.unpack_from("<Q", raw, off + 4)[0]
        ln = struct.unpack_from("<Q", raw, off + 12)[0]
        off += 20
        if not ln:
            continue
        if t == 7:
            if flags & 0x0200:          # CM_RESOURCE_MEMORY_LARGE_40
                ln <<= 8
            elif flags & 0x0400:        # CM_RESOURCE_MEMORY_LARGE_48
                ln <<= 16
            elif flags & 0x0800:        # CM_RESOURCE_MEMORY_LARGE_64
                ln <<= 32
        if t in (3, 7) and lo + ln > lo:
            out.append((lo, lo + ln))
    if not out:
        return [], "no memory descriptors (len=%d count=%d)" % (len(raw), count)
    return out, "ok"


def _minus(ranges, cut):
    """ranges - cut, both [(lo, hi)]."""
    for c, d in cut:
        nxt = []
        for s, e in ranges:
            if d <= s or c >= e:
                nxt.append((s, e))
                continue
            if s < c:
                nxt.append((s, c))
            if d < e:
                nxt.append((d, e))
        ranges = nxt
    return ranges


def usable_ranges(top, lo=None, hi=None, bad=None):
    """Scan plan: declared RAM, clamped to `top`, minus BADPA, minus the window.

    Falls back to the old HOLES map (and says so) when the resource map cannot
    be read -- that fallback still walks the PCI hole, which is how p40d's scan
    bugchecked."""
    top = min(top, 0x4000000000) if top else 0x100000000
    good, note = ram_map()
    if not good:
        out = []
        cur = SCAN_LO
        for rlo, rhi in sorted(HOLES):
            if rhi <= cur:
                continue
            if rlo >= top:
                break
            if rlo > cur:
                out.append((cur, min(rlo, top)))
            cur = max(cur, rhi)
            if cur >= top:
                break
        if cur < top:
            out.append((cur, top))
        note = "FALLBACK holes: " + note
    else:
        bad = load_bad() if bad is None else bad
        note = "map=%d bad=%d" % (len(good), len(bad))
        good = _minus([(a, min(b, top)) for a, b in good if a < top], bad)
    lo = SCAN_LO if lo is None else lo
    hi = top if hi is None else min(hi, top)
    out = []
    for a, b in good:
        a, b = max(a, lo), min(b, hi)
        a, b = (a + 0xFFF) & ~0xFFF, b & ~0xFFF
        if b > a:
            out.append((a, b))
    return sorted(out), note


def name_hits(g, ranges, chunk=SCAN_CHUNK, cap=HIT_CAP):
    """Physical addresses of the NAME string; a faulted chunk is retried at 4 KiB.

    p43q skipped 70140 of 454583 chunks (15.4% of RAM, ~4.3 GiB) because one
    bad page poisons the whole 64 KiB ioctl -- and those holes were never read
    back.  A fault is therefore re-read page by page: good pages are scanned, a
    bad page only breaks the carry.  The carry is 14 bytes (NAME-1) and spans
    both chunk and page boundaries.  Every hit and a periodic checkpoint go
    straight to PROG, so a box hang keeps the evidence.
    """
    hits = []
    skipped = 0
    chunks = 0
    rescued = 0
    scanned = 0
    nxt_ck = CKPT_BYTES
    keep = len(NAME) - 1
    for rlo, rhi in ranges:
        pa = rlo
        carry = b""
        while pa < rhi and len(hits) < cap:
            n = min(chunk, rhi - pa)
            if THROTTLE_MS and ((pa >> 16) & 0x3F) == 0:
                time.sleep(THROTTLE_MS / 1000.0)
            try:
                blk = g.read_phys(pa, n)
            except OSError:
                chunks += 1
                bad = 0
                for sub in range(0, n, PAGE):
                    sn = min(PAGE, n - sub)
                    try:
                        sblk = g.read_phys(pa + sub, sn)
                    except OSError:
                        bad += 1
                        carry = b""
                        continue
                    rescued += 1
                    buf2 = carry + sblk
                    base = pa + sub - len(carry)
                    off = 0
                    while len(hits) < cap:
                        i = buf2.find(NAME, off)
                        if i < 0:
                            break
                        hits.append(base + i)
                        prog("HIT pa=%#x (%d)" % (base + i, len(hits)))
                        off = i + 1
                    carry = sblk[-keep:]
                skipped += bad
                prog("FAULT pa=%#x n=%#x bad4k=%d rescued=%d"
                     % (pa, n, bad, n // PAGE - bad))
                pa += n
            else:
                chunks += 1
                buf2 = carry + blk
                base = pa - len(carry)
                off = 0
                while len(hits) < cap:
                    i = buf2.find(NAME, off)
                    if i < 0:
                        break
                    hits.append(base + i)
                    prog("HIT pa=%#x (%d)" % (base + i, len(hits)))
                    off = i + 1
                carry = blk[-keep:]
                pa += n
            scanned += n
            if scanned >= nxt_ck:
                prog("CKPT pa=%#x scanned=%d MiB chunks=%d hits=%d fault=%d "
                     "rescued=%d %.1fs"
                     % (pa, scanned >> 20, chunks, len(hits), skipped, rescued,
                        time.perf_counter() - _T0))
                nxt_ck += CKPT_BYTES
    prog("SCANEND scanned=%d MiB chunks=%d hits=%d fault=%d rescued=%d %.1fs"
         % (scanned >> 20, chunks, len(hits), skipped, rescued,
            time.perf_counter() - _T0))
    if len(hits) >= cap:
        prog("SCANEND CAP REACHED cap=%d -- coverage TRUNCATED" % cap)
    return hits, skipped, chunks, rescued


def valid_cr3(g, dtb):
    """Plausible CR3: a real frame inside usable RAM.

    p43h: the old gate also demanded (dtb & 0xFFF) == 0, but a DTB carries a
    PCID in the low bits (logged 0x3abe738c0), so the frame is masked first and
    only the frame is asked against the RAM map -- the raw value is never
    required to be page aligned.
    """
    frame = dtb & MASK
    return frame >= SCAN_LO and frame < g.ram_top and g.is_ram(frame)


def is_kva(x, lane=LINK_OFF):
    """Kernel virtual address whose page offset matches that LIST_ENTRY lane.

    A LIST_ENTRY points at the *same* field in the neighbour, so flink stays on
    lane LINK_OFF and blink on lane LINK_OFF+8; p43h: checking both against
    LINK_OFF made every real blink score nothing.
    """
    return (x >> 48) == 0xFFFF and (x & 0xFFF) == lane



HEX_WIN = ((0x3a0, 0x40),)   # (back, fwd): type..pc, one window on the base


def hex_probe(g, hits, win=HEX_WIN):
    """--hex: dump fixed windows around every hit page.

    A page carrying two or more copies used to be skipped as "a string table,
    not an _EPROCESS", and that quietly excluded the one page the pid+dtb gate
    actually accepted (p43n: five hits on 0x312862000, its base on the page
    below, and no bytes anywhere).  Multi-hit pages are therefore dumped too,
    after the solo ones and with every hit of the page shown, so an accepted
    base can always be read back.  Each block is one hit: `hit=i/n` says which
    of how many; the base is still `hit - delta`, never the block start.

    On single-hit pages one window is printed as offset/value rows --
    [hit-0x3a0, hit+0x40] -- so the real field offsets are read off the bytes
    instead of inferred from a score.  On 26200 that window carries the whole
    head: base at hit-0x338, dispatcher type at the base, DirectoryTableBase at
    hit-0x310, UniqueProcessId at hit-0x168, the links, token, PEB, and on past
    the name to the PriorityClass byte at hit+0x0f.

    p43u: the old two windows sat either side of the 26200 base and skipped the
    exact range the base needs -- one window now spans it, because a gap in the
    evidence was misread as a miss twice.
    """
    pages = {}
    for h in hits:
        pages.setdefault(h & ~0xFFF, []).append(h)
    solo = [p for p, hs in pages.items() if len(hs) == 1]
    multi = [p for p, hs in pages.items() if len(hs) > 1]
    log("HEX pages=%d solo=%d multi=%d win=%s"
        % (len(pages), len(solo), len(multi),
           ",".join("%+#x..%+#x" % (-b, f) for b, f in win)))
    for page in solo + multi:
        hs = sorted(pages[page])
        try:
            p = g.read_phys(page - PAGE_BACK, 0x2000)
        except OSError as e:
            log("  %#x fault %s" % (page, e))
            continue
        for i, hit in enumerate(hs):
            hb = hit - page + PAGE_BACK
            log("  == hit=%#x hit=%d/%d" % (hit, i + 1, len(hs)))
            for back, fwd in win:
                lo = max(hb - back, 0)
                hi = min(hb + fwd + 8, len(p))
                # a hit near the page end clamps hi to a non-8-aligned tail; the
                # last row would then unpack 8 bytes past the buffer (p43m
                # crash), so stop at the last full qword and mark what was
                # dropped.
                while lo + 8 <= hi:
                    x = struct.unpack_from("<Q", p, lo)[0]
                    tag = "<< name" if abs(lo - hb) < 8 else ""
                    log("    %#x rel=%+#06x %016x %s"
                        % (page + lo - PAGE_BACK, lo - hb, x, tag))
                    lo += 8
                if lo < hi:
                    log("    tail %d bytes: %s" % (hi - lo, p[lo:hi].hex()))


def candidates_for(g, pid, hits):
    """Dedupe cr3 candidates: name page -> signed delta -> name+pid+shape+DTB.

    The name is ImageFileName *inside* the object, so the base lies up to 0x360
    bytes BELOW the hit; one page before the hit is read to carry it -- and if
    only that back page faults, the hit page is read alone and the base is used
    only when it falls inside it (hit offset >= 0x338).

    p43u 26200: the base is verified, not assumed.  At every delta the bytes at
    base+0x338 must still read back as NAME and a pid must sit in PID_OFFS --
    the string is fixed relative to the base, so a wrong delta cannot borrow a
    pid from a neighbour.  On top of that the 26200 shape is scored: dispatcher
    type 3, the PriorityClass byte right after the name (2 = normal), KVA links
    on the ActiveProcessLinks lane, a KVA token and a sane user PEB.  Below
    MIN_SCORE a "shape" is noise.  The pid is a filter; the frame at +0x28
    stays the verdict.

    p43o: every hit on a page is tried, not just the lowest.  Collapsing a page
    to min(hit) meant a multi-hit page could only ever produce one base, chosen
    by lowest address rather than by the gate -- and the single accepted page
    of p43n was exactly such a page.
    """
    out = []
    seen = set()
    by_page = {}
    for h in hits:
        by_page.setdefault(h & ~0xFFF, []).append(h)
    for page, hs in by_page.items():
        pbase = page - PAGE_BACK
        p = None
        try:
            p = g.read_phys(pbase, 0x2000)      # back page + hit page
        except OSError:
            # The base may live in the hit page itself (hit offset >= 0x338);
            # losing the whole candidate because its neighbour is unreadable is
            # what kept p43u at "back page faulted (skip)" on a fifth of the
            # hits.  Try the hit page alone and let the offsets say whether the
            # base is reachable at all.
            pbase = page
            try:
                p = g.read_phys(pbase, 0x1000)
            except OSError:
                log("  cand page=%#x both pages faulted (skip)" % page)
                continue
            log("  cand page=%#x back page faulted, hit page only" % page)
        for hit in sorted(hs):
            hb = hit - pbase                            # hit offset inside p
            for d in NAME_DELTAS:
                b = hb + d
                if b < 0 or b + NEED > len(p):
                    continue
                if p[b + OFF_NAME:b + OFF_NAME + len(NAME)] != NAME:
                    continue                            # base does not hold the name
                offs = [o for o in PID_OFFS
                        if struct.unpack_from("<I", p, b + o)[0] == pid]
                if not offs:
                    continue
                dtb = struct.unpack_from("<Q", p, b + 0x28)[0]
                otype = p[b]
                if not valid_cr3(g, dtb):
                    log("  cand page=%#x hit=%#x delta=%#x pid@%#x type=%d "
                        "dtb=%#x (reject)" % (page, hit, d, offs[0], otype, dtb))
                    continue
                score = 0
                if otype == 3:
                    score += 2                  # ProcessObject dispatcher type
                pc = p[b + PC_OFF]
                if pc == 2:
                    score += 4                  # NORMAL_PRIORITY_CLASS signature
                elif 0 < pc <= 0x20:
                    score += 2
                if d == -OFF_NAME:
                    score += 4
                for lane in (LINK_OFF, LINK_OFF + 8):
                    if is_kva(struct.unpack_from("<Q", p, b + lane)[0], lane):
                        score += 2              # LIST_ENTRY flink/blink shape
                for lane in (LINK_ALT, LINK_ALT + 8):
                    if is_kva(struct.unpack_from("<Q", p, b + lane)[0], lane):
                        score += 1              # symbol-table lane, weaker
                if struct.unpack_from("<Q", p, b + OFF_TOKEN)[0] >> 48 == 0xFFFF:
                    score += 2                  # Token: _EX_FAST_REF is a KVA
                peb = struct.unpack_from("<Q", p, b + OFF_PEB)[0]
                if 0 < peb < 0x800000000000 and not (peb & 7):
                    score += 2                  # PEB is a user VA, 8-aligned
                if score < MIN_SCORE:
                    log("  cand page=%#x hit=%#x delta=%#x pid@%#x dtb=%#x "
                        "score=%d (reject)" % (page, hit, d, offs[0], dtb, score))
                    continue
                key = (page, hit, d)
                if key in seen:
                    continue
                seen.add(key)
                out.append((score, hit + d, dtb))
    out.sort(key=lambda c: -c[0])
    if not out:
        log("  %d hit pages, none passed the name+pid+shape+dtb gate" % len(by_page))
    return out


# ---------------------------------------------------------------- pe check
def validate_pe(buf):
    """Strict PE32+ header check on a 4 KiB page buffer."""
    if len(buf) < 0x1000 or buf[:2] != b"MZ":
        return None
    elf = struct.unpack_from("<I", buf, 0x3C)[0]
    if not (0x40 <= elf <= 0xF00) or buf[elf:elf + 4] != b"PE\x00\x00":
        return None
    machine, nsec = struct.unpack_from("<HH", buf, elf + 4)
    sizeopt = struct.unpack_from("<H", buf, elf + 20)[0]
    if machine != 0x8664 or not (1 <= nsec <= 40) or sizeopt < 0xF0:
        return None
    if struct.unpack_from("<H", buf, elf + 24)[0] != 0x20B:
        return None
    salign, sizeimg, sizehdr = struct.unpack_from("<III", buf, elf + 32)[0], \
        struct.unpack_from("<I", buf, elf + 56)[0], \
        struct.unpack_from("<I", buf, elf + 60)[0]
    if salign != 0x1000 or not (MIN_IMAGE <= sizeimg <= MAX_IMAGE):
        return None
    if not (0x200 <= sizehdr <= 0x1000):
        return None
    if elf + 24 + sizeopt + 40 * nsec > 0x1000:
        return None
    secs = []
    so = elf + 24 + sizeopt
    for i in range(nsec):
        o = so + 40 * i
        name = buf[o:o + 8].rstrip(b"\x00").decode("latin-1")
        vsize, va, rsize = struct.unpack_from("<III", buf, o + 8)
        vsize = vsize or rsize
        if va >= sizeimg:
            continue
        vsize = min(vsize, sizeimg - va)
        secs.append((name, va, vsize))
    return {"size": sizeimg, "hdr": sizehdr, "secs": secs}


# ---------------------------------------------------------------- page walk
def u64(buf, off):
    return struct.unpack_from("<Q", buf, off)[0]


def retry_phys(g, pa, n, tries=3):
    """Physical read with a short retry.

    p43x lost all three walks to errno 1450 on a page that had read fine
    seconds earlier: gdrv3 fails transiently under load, and one lost table
    read used to look exactly like a bad frame.  h320: after the 630k-rescue
    sweep, 1450 persists well past 150 ms, so the backoff scales with the try.
    """
    for i in range(tries):
        try:
            return g.read_phys(pa, n)
        except OSError:
            if i == tries - 1:
                raise
            time.sleep(RETRY_MS / 1000.0 * (i + 1))


class Walk(object):
    """CR3 -> VA page resolution; tables cached, every PA is_ram-checked.

    The PCID in CR3 bits 0-11 is dropped before the first read: a physical read
    at frame|PCID lands 0x8c0 bytes into the page, so every PML4/PDPT/PD slot is
    sampled 280 entries off.  p43i walked the raw value and found no PE.

    p43y: the PML4 entry is resolved per VA instead of being fixed to [0].
    r5apex_dx12.exe is mapped at 0x7ff6..., which is PML4 index 0xff, so the
    old PML4[0]-only walk could not have found its image page even with a
    correct DTB.
    """

    def __init__(self, g, cr3):
        self.g = g
        self.raw = cr3
        self.cr3 = cr3 & MASK
        self.pml4 = retry_phys(g, self.cr3, 0x1000, tries=8)    # PML4
        e0 = u64(self.pml4, 0)
        self.e0 = e0                            # kept for --why, not for logic
        self.pdpt_pa = (e0 & MASK) if (e0 & 1) and g.is_ram(e0 & MASK) else 0
        self.cache = {}

    def _table(self, pa):
        if pa not in self.cache:
            try:
                self.cache[pa] = retry_phys(self.g, pa, 0x1000)
            except OSError:
                self.cache[pa] = None
        return self.cache[pa]

    def pt_for(self, va):
        e4 = u64(self.pml4, ((va >> 39) & 0x1FF) * 8)
        if not (e4 & 1) or (e4 & 0x80) or not self.g.is_ram(e4 & MASK):
            return None
        pdpt = self._table(e4 & MASK)
        if pdpt is None:
            return None
        e = u64(pdpt, ((va >> 30) & 0x1FF) * 8)
        if not (e & 1) or (e & 0x80) or not self.g.is_ram(e & MASK):
            return None
        pd = self._table(e & MASK)
        if pd is None:
            return None
        d = u64(pd, ((va >> 21) & 0x1FF) * 8)
        if not (d & 1) or (d & 0x80) or not self.g.is_ram(d & MASK):
            return None
        return self._table(d & MASK)

    def page_pa(self, va):
        pt = self.pt_for(va)
        if pt is None:
            return None
        pte = u64(pt, ((va >> 12) & 0x1FF) * 8)
        if not (pte & 1):
            return None
        pa = pte & MASK
        return pa if self.g.is_ram(pa) else None


def probe_dtb(g, dtb):
    """One-line census of why a walk dies: which level is absent, or none.

    "walk -> no PE" covered four different faults at once, so a real frame whose
    image page happened to be trimmed (or whose PML4 entry went non-present
    between scans) read exactly like a garbage frame.  p43o separates them:
    pml4[0] absent / pml4[0] not RAM / no RAM PD / no RAM PT / RAM leaves but no
    MZ.  Read-only, and bounded so a wild frame cannot stall the probe.
    """
    try:
        w = Walk(g, dtb)
    except OSError as e:
        return "pml4 fault %s" % e
    if not w.pdpt_pa:
        # PML4[0] is often empty for a 64-bit process (image at index 0xff), so
        # name the highest present entry instead of letting "empty [0]" read as
        # "no address space".
        hi = -1
        for i in range(511, -1, -1):
            if u64(w.pml4, i * 8) & 1:
                hi = i
                break
        return "pml4[0]=%016x %s alt_pml4=%d" % (
            w.e0, "not-ram/absent" if not (w.e0 & 1) else "pdpt not-ram", hi)
    try:
        pdpt = g.read_phys(w.pdpt_pa, 0x1000)
    except OSError as e:
        return "pml4[0]=%016x pdpt fault %s" % (w.e0, e)
    pd_n = pt_n = leaf = mz = 0
    for ii in range(256):
        e = u64(pdpt, ii * 8)
        if not (e & 1) or (e & 0x80):
            continue
        try:
            if not g.is_ram(e & MASK):
                continue
            pd_n += 1
            pd = g.read_phys(e & MASK, 0x1000)
        except OSError:
            continue
        for jj in range(512):
            d = u64(pd, jj * 8)
            if not (d & 1) or (d & 0x80) or not g.is_ram(d & MASK):
                continue
            pt_n += 1
            try:
                pt = g.read_phys(d & MASK, 0x1000)
            except OSError:
                continue
            for kk in range(512):
                pte = u64(pt, kk * 8)
                if not (pte & 1) or not g.is_ram(pte & MASK):
                    continue
                leaf += 1
                if leaf > 60000:            # enough for a verdict
                    break
                try:
                    if g.read_phys(pte & MASK, 2) == b"MZ":
                        mz += 1
                except OSError:
                    pass
    return ("pml4[0]=%016x pdpt ram pd=%d pt=%d leaf=%d mz=%d"
            % (w.e0, pd_n, pt_n, leaf, mz))


def find_mz(g, cr3):
    """First page in any PML4 entry that passes validate_pe -> (va, meta).

    p43y: PML4 entries are walked in descending order.  The exe and the DLLs of
    a 64-bit process are mapped at 0x7ff6../0x7ffd.., i.e. near PML4 index 0xff,
    so descending order finds the image before the (much larger) heap.  A 2 MiB
    page is probed at its base only; every PA must be RAM.
    """
    w = Walk(g, cr3)
    probe = 0
    for i4 in range(511, -1, -1):
        e4 = u64(w.pml4, i4 * 8)
        if not (e4 & 1) or (e4 & 0x80) or not g.is_ram(e4 & MASK):
            continue
        try:
            pdpt = retry_phys(g, e4 & MASK, 0x1000)
        except OSError:
            continue
        for ii in range(512):
            e = u64(pdpt, ii * 8)
            if not (e & 1) or (e & 0x80):
                continue
            pd_pa = e & MASK
            if not g.is_ram(pd_pa):
                continue
            try:
                pd = retry_phys(g, pd_pa, 0x1000)
            except OSError:
                continue
            for jj in range(512):
                d = u64(pd, jj * 8)
                if not (d & 1):
                    continue
                if d & 0x80:                    # 2 MiB page: probe page 0 only
                    base_va = (i4 << 39) | (ii << 30) | (jj << 21)
                    pa = d & MASK
                    probe += 1
                    if base_va >= 0x10000 and g.is_ram(pa):
                        try:
                            if retry_phys(g, pa, 2) == b"MZ":
                                meta = validate_pe(retry_phys(g, pa, 0x1000))
                                if meta:
                                    return base_va, meta
                        except OSError:
                            pass
                    continue
                pt_pa = d & MASK
                if not g.is_ram(pt_pa):
                    continue
                try:
                    pt = retry_phys(g, pt_pa, 0x1000)
                except OSError:
                    continue
                for kk in range(512):
                    pte = u64(pt, kk * 8)
                    if not (pte & 1):
                        continue
                    pa = pte & MASK
                    if not g.is_ram(pa):
                        continue
                    probe += 1
                    if probe > PTE_CAP:
                        return None
                    try:
                        if retry_phys(g, pa, 2) != b"MZ":
                            continue
                        meta = validate_pe(retry_phys(g, pa, 0x1000))
                    except OSError:
                        continue
                    if meta:
                        return ((i4 << 39) | (ii << 30) | (jj << 21)
                                | (kk << 12)), meta
    return None


# ---------------------------------------------------------------- dump
class Stats(object):
    def __init__(self):
        self.read = 0
        self.zero = 0
        self.fail = 0


def flush_run(g, buf, va, pa, n, st):
    try:
        buf[va:va + n] = retry_phys(g, pa, n)
        st.read += n
    except OSError:
        st.fail += n


def dump_range(g, w, buf, base, off0, size, st):
    """Copy [base+off0, +size) into buf at off0, present pages only."""
    va, off = base + off0, off0
    end = off0 + size
    run_va = run_pa = run_len = None
    while off < end:
        n = min(PAGE - (va & 0xFFF), end - off)
        pa = w.page_pa(va)
        if pa is not None:
            if run_va is not None and pa == run_pa + run_len:
                run_len += n
            else:
                if run_va is not None:
                    flush_run(g, buf, run_va, run_pa, run_len, st)
                run_va, run_pa, run_len = va, pa, n
        else:
            if run_va is not None:
                flush_run(g, buf, run_va, run_pa, run_len, st)
                run_va = run_len = None
            st.zero += n
        va += n
        off += n
    if run_va is not None:
        flush_run(g, buf, run_va, run_pa, run_len, st)


def pid_alive(pid):
    h = kernel32.OpenProcess(0x1000, False, pid)
    if h:
        kernel32.CloseHandle(h)
        return True
    return False


# ---------------------------------------------------------------- main
def elevated_main(pid):
    log("p40d dumplive  %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
    log("pure-read probe: device open only; no load/DSE/service touch")
    log("pid=%d alive=%s" % (pid, pid_alive(pid)))
    try:
        g = gio.Gio(chunk=OPT["chunk"])
    except OSError as e:
        log("FATAL: %s" % e)
        return _finish(1, "FATAL no transport")
    log("PRE ram_top=%#x installed=%d MiB" % (g.ram_top, g.ram_top // 0x100000))
    log("window lo=%s hi=%s chunk=%#x"
        % ("-" if OPT["lo"] is None else "%#x" % OPT["lo"],
           "-" if OPT["hi"] is None else "%#x" % OPT["hi"], OPT["chunk"]))
    # R5: the layout is the variable that changed, so it is logged, in both
    # streams, and names the build it belongs to.
    log("LAYOUT win26200 name=%dB off_name=%#x pc=%#x deltas=%+#x..%+#x "
        "pid_offs=%#x..%#x link=%#x min_score=%d"
        % (len(NAME), OFF_NAME, PC_OFF, NAME_DELTAS.start, NAME_DELTAS.stop,
           PID_OFFS.start, PID_OFFS.stop, LINK_OFF, MIN_SCORE))
    prog("LAYOUT win26200 name_len=%d off_name=%#x pc_off=%#x delta_lo=%+#x "
         "delta_hi=%+#x pid_lo=%#x pid_hi=%#x link=%#x min_score=%d"
         % (len(NAME), OFF_NAME, PC_OFF, NAME_DELTAS.start, NAME_DELTAS.stop,
            PID_OFFS.start, PID_OFFS.stop, LINK_OFF, MIN_SCORE))
    prog("START pid=%d alive=%s lo=%s hi=%s chunk=%#x"
         % (pid, pid_alive(pid), OPT["lo"], OPT["hi"], OPT["chunk"]))
    ranges, note = usable_ranges(g.ram_top, OPT["lo"], OPT["hi"])
    total = sum(b - a for a, b in ranges)
    log("RAMMAP %s ranges=%d total=%d MiB" % (note, len(ranges), total >> 20))
    prog("RAMMAP %s ranges=%d total=%d MiB" % (note, len(ranges), total >> 20))
    for a, b in ranges:
        log("  scan %#x-%#x (%.1f MiB)" % (a, b, (b - a) / 1048576.0))
        prog("RANGE %#x-%#x" % (a, b))
    if not ranges:
        g.close()
        return _finish(2, "NO_RANGES")

    hits, skipped, chunks, rescued = name_hits(g, ranges, chunk=OPT["chunk"])
    log("scan: %d hits, %d/%d chunks faulted, %d pages rescued at %#x, %.1f s"
        % (len(hits), skipped, chunks, rescued, OPT["chunk"],
           time.perf_counter() - _T0))
    if not hits and skipped:
        log("retry scan at %#x chunks" % PAGE)
        g.chunk = PAGE
        OPT["chunk"] = PAGE
        prog("RETRY at %#x chunks" % PAGE)
        hits, skipped, chunks, rescued = name_hits(g, ranges, chunk=PAGE)
        log("retry: %d hits, %d/%d chunks faulted, %.1f s"
            % (len(hits), skipped, chunks, time.perf_counter() - _T0))
    for h in hits:
        log("  hit %#x" % h)
    if not hits:
        g.close()
        return _finish(2, "NO_HITS")

    cands = candidates_for(g, pid, hits)
    log("candidates: %d" % len(cands))
    if OPT["hex"] or not cands:
        hex_probe(g, hits)
    for score, base, dtb in cands:
        log("  eprocess=%#x dtb=%#x score=%d" % (base, dtb, score))
    if not cands:
        g.close()
        return _finish(3, "NO_CR3")

    found = None
    for score, base, dtb in cands:
        t0 = time.perf_counter()
        try:
            r = find_mz(g, dtb)
        except OSError as e:
            log("  walk dtb=%#x fault %s" % (dtb, e))
            continue
        if r:
            log("  walk dtb=%#x -> image va=%#x (%d secs, %.1f s)"
                % (dtb, r[0], len(r[1]["secs"]), time.perf_counter() - t0))
            found = (base, dtb, r[0], r[1])
            break
        log("  walk dtb=%#x -> no PE" % dtb)
        if OPT["why"]:
            log("  why  dtb=%#x %s" % (dtb, probe_dtb(g, dtb)))
    if not found:
        g.close()
        return _finish(4, "NO_MZ")

    ebase, dtb, base_va, meta = found
    log("chosen eprocess=%#x dtb=%#x image_va=%#x size=%#x hdr=%#x"
        % (ebase, dtb, base_va, meta["size"], meta["hdr"]))
    try:
        st = Stats()
        buf = bytearray(meta["size"])
        w = Walk(g, dtb)
        dump_range(g, w, buf, base_va, 0, meta["hdr"], st)     # headers
        for name, va, vsize in meta["secs"]:
            before = st.read
            dump_range(g, w, buf, base_va, va, vsize, st)
            log("  sec %-8.8s va=%#010x size=%#x read=%d"
                % (name, va, vsize, st.read - before))
    except OSError as e:
        g.close()
        return _finish(5, "DUMP_FAULT %s" % e)

    out_bin = os.path.join(ROOT, "temp", "r5apex_live_%s_%d.bin"
                           % (time.strftime("%Y%m%d_%H%M%S"), pid))
    os.makedirs(os.path.dirname(out_bin), exist_ok=True)
    with open(out_bin, "wb") as f:
        f.write(buf)
    sha = hashlib.sha256(buf).hexdigest()
    log("DUMP %s size=%#x sha256=%s" % (out_bin, len(buf), sha))
    log("pages read=%d zero=%d fail=%d alive-end=%s"
        % (st.read // PAGE, st.zero // PAGE, st.fail // PAGE, pid_alive(pid)))
    for code in sorted(g.stats):
        log("  stat %s" % g.stat_line(code))
    g.close()
    if st.read < 0x4000000 or st.fail:
        return _finish(6, "DUMP_PARTIAL read=%d fail=%d" % (st.read, st.fail))
    return _finish(0, "DUMP_OK %s %s" % (out_bin, sha))


def _finish(code, verdict):
    log("elapsed %.1f s" % (time.perf_counter() - _T0))
    log("VERDICT: %s" % verdict)
    try:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
    except OSError as e:
        print("could not write %s: %s" % (OUT, e))
    return code


def print_ranges():
    """Dry run (p43b): print the scan plan, no device, no elevation."""
    good, note = ram_map()
    top = OPT["ram_top"] or (max(b for _, b in good) if good else 0x100000000)
    bad = load_bad()
    ranges, plnote = usable_ranges(top, OPT["lo"], OPT["hi"], bad=bad)
    print("map note=%s ranges=%d top=%#x" % (note, len(good), top))
    for a, b in good:
        print("  map %#x-%#x (%.1f MiB)" % (a, b, (b - a) / 1048576.0))
    print("badpa %d from %s" % (len(bad), BADPA_FILE))
    print("plan %s ranges=%d" % (plnote, len(ranges)))
    tot = 0
    for a, b in ranges:
        print("  scan %#x-%#x (%.1f MiB)" % (a, b, (b - a) / 1048576.0))
        tot += b - a
    print("total %d MiB (%.2f GiB) over %d range(s)"
          % (tot >> 20, tot / 1073741824.0, len(ranges)))
    if top and good and top > max(b for _, b in good):
        print("NOTE ram_top %#x is above the map top; nothing to clamp" % top)
    return 0


def main():
    pid = None
    for a in sys.argv:
        if a.startswith("--pid="):
            pid = int(a.split("=", 1)[1])
        elif a.startswith("--lo="):
            OPT["lo"] = int(a.split("=", 1)[1], 0)
        elif a.startswith("--hi="):
            OPT["hi"] = int(a.split("=", 1)[1], 0)
        elif a.startswith("--chunk="):
            OPT["chunk"] = int(a.split("=", 1)[1], 0)
        elif a.startswith("--ram-top="):
            OPT["ram_top"] = int(a.split("=", 1)[1], 0)
        elif a == "--inplace":
            OPT["inplace"] = True
        elif a == "--hex":
            OPT["hex"] = True
        elif a == "--why":
            OPT["why"] = True
    if "--print-ranges" in sys.argv:
        return print_ranges()
    rest = [a for a in sys.argv[1:] if not a.startswith("--")]
    if pid is None and rest:
        try:
            pid = int(rest[0])
        except ValueError:
            pass
    if pid is None:
        pid = find_pid()
    if not pid:
        print("no r5apex_dx12 process found")
        return 2
    if OPT["inplace"] or elevation() == 1 or "--elevated" in sys.argv:
        if elevation() != 1:
            log("WARNING: --inplace/--elevated but token is NOT elevated; "
                "device open will likely fail with err=5")
        return elevated_main(pid)
    args = [sys.executable, os.path.abspath(sys.argv[0]), "--elevated",
            "--pid=%d" % pid]
    if OPT["hex"]:
        args.append("--hex")
    if OPT["why"]:
        args.append("--why")
    if OPT["lo"] is not None:
        args.append("--lo=%#x" % OPT["lo"])
    if OPT["hi"] is not None:
        args.append("--hi=%#x" % OPT["hi"])
    if OPT["chunk"] != SCAN_CHUNK:
        args.append("--chunk=%#x" % OPT["chunk"])
    params = subprocess.list2cmdline(args)
    try:
        os.remove(OUT)
    except OSError:
        pass
    print("parent: elevating for pid=%d" % pid)
    print("parent: params=%s" % params)
    msg = run_elevated(params)
    print(msg)
    if not os.path.exists(OUT):
        # The child can die before _finish() ever runs (p40f: exit -1 in 7 ms).
        # Leave the reason on disk so OUT is never silently absent.
        LOG.append("parent: elevation returned %r" % msg)
        return _finish(3, "ELEV_FAIL %s" % msg)
    print("--- %s" % OUT)
    print(open(OUT, encoding="utf-8").read())
    return 0


_T0 = time.perf_counter()
if __name__ == "__main__":
    sys.exit(main())


