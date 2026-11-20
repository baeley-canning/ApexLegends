r"""qk_va.py -- ZERO-ATTACH virtual-address reader + --emit feed producer.

WHY THIS EXISTS
    gdrv3's read path (MmMapIoSpace in the caller's own context) never attaches
    to the game's address space, so the only kernel footprint is the already-
    resident vendor-signed driver image.  History: the 07/11 game terminations
    followed apexdrv's per-IOCTL KeStackAttachProcess; that CUSTOM driver is
    RETIRED (removed from this file 19/11, sources archived to
    _attic_apexdrv/).  We are strictly gdrv3 only.

TRANSPORT (policy 2026-11-19, now enforced in code)
    gdrv3 ONLY.  There is no --driver flag any more: a mixed-transport session
    is unmeasurable evidence and a custom mapped driver is its own detection
    surface.  If gdrv3 refuses a page (e.g. 1450 on some live PML4 frames),
    the page reports as FAULTED - never papered over by another transport.
    Usermode ReadProcessMemory is not an alternative either (OpenProcess
    succeeds but every read of the game returned 87; h413/h414/h415, 18/11).

DTB
    Cached in temp\qk_dtb_<pid>.txt together with the image base, so only the
    first run of a game session pays the discovery (~70-80 s via p72_ppath's
    pid scan).  A new game process => new pid => fresh discovery.

USAGE
    python ext\qk_va.py --pe                     # image base + MZ + sections
    python ext\qk_va.py --at=0x7FF721690000 --len=64
    python ext\qk_va.py --array=0xB675E68 --slots=64     # pointer array -> entities
    python ext\qk_va.py --watch=600 --at=<base>          # Stage 1b survival gate
    python ext\qk_va.py --emit [--hz=10] [--secs=300]    # PLAN 1 feed producer
                                                 # -> temp\qk_feed.json
    --no-driver is still parsed (accepted, no-op): existing rituals pass it.

EXIT   0 ok | 2 no driver | 3 no game | 4 no dtb | 5 read failed | 6 feed partial
"""
import bisect
import json
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gio            # noqa: E402
import dumplive as dl  # noqa: E402

ROOT = os.path.dirname(HERE)
TMP = os.path.join(ROOT, "temp")

LOG = []
OUT_PATH = None
VA_THROTTLE = 0     # mirror of dl.THROTTLE_MS for qk_va's own scans (set by callers)


def set_out(p):
    """Truncate the evidence file and remember it; every line is appended live."""
    global OUT_PATH
    OUT_PATH = os.path.abspath(p) if p else None
    if OUT_PATH:
        try:
            os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
            with open(OUT_PATH, "w", encoding="utf-8") as f:
                f.write("")
        except OSError:
            pass


def out(s):
    line = str(s)
    print(line)
    LOG.append(line)
    if OUT_PATH:
        try:
            with open(OUT_PATH, "a", encoding="utf-8") as f:   # live: tail-able
                f.write(line + "\n")
        except OSError:
            pass


def flush(path):
    if not path:
        return
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(LOG) + "\n")
    except OSError as e:
        print("could not write %s: %s" % (path, e))


def arg(name, default=None, cast=str):
    for i, a in enumerate(sys.argv):
        if a == "--" + name and i + 1 < len(sys.argv):
            return cast(sys.argv[i + 1])
        if a.startswith("--" + name + "="):
            return cast(a.split("=", 1)[1])
    return default


def flag(name):
    return ("--" + name) in sys.argv


# --------------------------------------------------------------- DTB cache
def dtb_file(pid):
    return os.path.join(TMP, "qk_dtb_%d.txt" % pid)


def load_cached(pid):
    p = dtb_file(pid)
    if not os.path.exists(p):
        return None
    try:
        with open(p, "r", encoding="utf-8") as f:
            k = {}
            for ln in f:
                if "=" in ln:
                    a, b = ln.strip().split("=", 1)
                    k[a] = int(b, 16) if b.lower().startswith("0x") else int(b)
            if k.get("pid") == pid and k.get("dtb"):
                return k
    except (OSError, ValueError):
        return None
    return None


def save_cache(pid, dtb, base):
    try:
        os.makedirs(TMP, exist_ok=True)
        with open(dtb_file(pid), "w", encoding="utf-8") as f:
            f.write("pid=%d\ndtb=0x%X\nbase=0x%X\nstamp=%d\n"
                    % (pid, dtb, base or 0, int(time.time())))
    except OSError:
        pass


# --------------------------------------------------------------- reader
class Reader(object):
    """VA -> PA through the page tables, then a physical read.  No attach."""

    def __init__(self, g, dtb):
        self.g = g
        self.w = dl.Walk(g, dtb)
        self.dtb = dtb
        self.reads = 0
        self.faults = 0

    def page_pa(self, va):
        return self.w.page_pa(va)

    def read(self, va, n):
        buf = bytearray()
        left = n
        cur = va
        while left > 0:
            pa = self.w.page_pa(cur)
            if pa is None:
                self.faults += 1
                return None
            off = cur & 0xFFF
            take = min(left, 0x1000 - off)
            try:
                # gdrv3 fails 1450 TRANSIENTLY (measured: the same frame refused at
                # 21:24 read fine at 22:35), so every page read retries with backoff.
                b = dl.retry_phys(self.g, pa + off, take, tries=6)
            except OSError:
                self.faults += 1
                return None
            self.reads += 1
            buf += b
            cur += take
            left -= take
        return bytes(buf)

    def u64(self, va):
        b = self.read(va, 8)
        return None if b is None else struct.unpack("<Q", b)[0]

    def u32(self, va):
        b = self.read(va, 4)
        return None if b is None else struct.unpack("<I", b)[0]


# --------------------------------------------------------------- discovery
class Ram(object):
    """The OS RAM map as an interval set - the ONLY safe guard for a raw PA read.

    gio.is_ram() is not enough: it only rejects >= ram_top and the 640K-1M hole,
    so an MMIO hole *inside* the map passes it and the raw read bugchecks the box
    (measured 07/11 21:34 - a hard reboot during a window scan).  Every physical
    read below goes through this.
    """

    def __init__(self, ranges):
        self.r = sorted(ranges)
        self.lo = [a for a, _ in self.r]

    def has(self, pa, n=1):
        i = bisect.bisect_right(self.lo, pa) - 1
        if i < 0:
            return False
        a, b = self.r[i]
        return a <= pa and pa + n <= b

    def page_ok(self, pa):
        return self.has(pa & ~0xFFF, 0x1000)


# KPROCESS.DirectoryTableBase sits at EPROCESS+0x28.  ImageFileName has been
# seen at each of these offsets across 19041..26200, so base = hit - off and the
# DTB is 0x28 bytes into that base: a read INSIDE the EPROCESS page, not a guess
# at an arbitrary frame.  (The previous approach tried every qword in the window
# as a CR3, which read arbitrary frames and hard-rebooted the box at 21:34.)
NAME_OFFS = (0x338, 0x450, 0x4C8, 0x5A0, 0x5A8, 0x5B0)


def _pml4_scan(g, ram, ranges, cap=60000):
    """Every 4 KiB page in RAM that looks like a page table (>=8 RAM-backed present entries).

    Reads 64 KiB at a time: one pass over 27.7 GB is ~150 s, versus ~8M 4 KiB ioctls.
    No EPROCESS offset is involved anywhere - a PML4 is recognised by its own shape.

    cap was 4096 until 08/11 03:3x: it filled inside the first few GB and `break`
    abandoned the whole sweep before the 12-16 GB band, where every DTB on this box
    has been, was ever read.  Density is ~1.3k/GB, so 60000 covers the 27 GB.
    """
    found = []
    for rlo, rhi in ranges:
        pa = (rlo + 0xFFF) & ~0xFFF
        while pa + 0x10000 <= rhi and len(found) < cap:
            if VA_THROTTLE and ((pa >> 16) & 0x3F) == 0:
                time.sleep(VA_THROTTLE / 1000.0)
            try:
                blk = dl.retry_phys(g, pa, 0x10000, tries=4)
            except OSError:
                pa += 0x10000
                continue
            for off in range(0, 0x10000, 0x1000):
                n = 0
                for i in range(0, 0x1000, 8):
                    e = struct.unpack_from("<Q", blk, off + i)[0]
                    if (e & 1) and not (e & 0x80):
                        f = e & 0xFFFFFFFFFF000
                        if f and ram.page_ok(f):
                            n += 1
                            if n >= 8:
                                break
                if n >= 8:
                    found.append(pa + off)
            pa += 0x10000
        if len(found) >= cap:
            break
    return found


def _image_size_of(rd, va):
    """SizeOfImage of the PE at va, or 0."""
    mz = rd.read(va, 2)
    if mz != b"MZ":
        return 0
    lf = rd.read(va + 0x3C, 4)
    if not lf:
        return 0
    elf = struct.unpack("<I", lf)[0]
    if not (0x40 <= elf <= 0x1000):
        return 0
    hdr = rd.read(va + elf, 0x60)
    if not hdr or hdr[:4] != b"PE\x00\x00":
        return 0
    return struct.unpack_from("<I", hdr, 0x50)[0]


def _peb_va(pid):
    """PEB virtual address for a pid, via NtQueryInformationProcess (an information
    call - granted by EAAC even when data-transfer calls are refused, per PHASE1 §11)."""
    import ctypes
    from ctypes import wintypes
    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.OpenProcess.restype = ctypes.c_void_p
    k32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    h = k32.OpenProcess(0x1000, False, pid)          # QUERY_LIMITED_INFORMATION
    if not h:
        return 0
    try:
        ntdll = ctypes.WinDLL("ntdll")

        class PBI(ctypes.Structure):
            _fields_ = [("Reserved1", ctypes.c_void_p),
                        ("PebBaseAddress", ctypes.c_void_p),
                        ("Reserved2", ctypes.c_void_p * 2),
                        ("UniqueProcessId", ctypes.c_void_p),
                        ("Reserved3", ctypes.c_void_p)]

        pbi = PBI()
        rl = wintypes.ULONG(0)
        st = ntdll.NtQueryInformationProcess(ctypes.c_void_p(h), 0, ctypes.byref(pbi),
                                             ctypes.sizeof(pbi), ctypes.byref(rl))
        if st != 0:
            return 0
        return pbi.PebBaseAddress or 0
    finally:
        k32.CloseHandle(ctypes.c_void_p(h))


def _scan_frames(g, ram, ranges, cap=500000, need=8):
    """Every 4 KiB page that looks like a page table.

    Speed matters: ONE struct.unpack per 64 KiB chunk, then a cheap bounds test per
    present entry.  No small cap - a cap of 40k filled with PTs before the scan
    reached the PML4 we wanted (measured 23:00).  need=8 trims obvious data pages.
    """
    found = []
    top = g.ram_top
    for rlo, rhi in ranges:
        pa = (rlo + 0xFFF) & ~0xFFF
        while pa + 0x10000 <= rhi and len(found) < cap:
            if VA_THROTTLE and ((pa >> 16) & 0x3F) == 0:
                time.sleep(VA_THROTTLE / 1000.0)
            try:
                blk = dl.retry_phys(g, pa, 0x10000, tries=2)
            except OSError:
                pa += 0x10000
                continue
            qs = struct.unpack_from("<%dQ" % (len(blk) // 8), blk)
            for base_off in range(0, len(qs), 512):
                n = 0
                for e in qs[base_off:base_off + 512]:
                    if (e & 1) and not (e & 0x80):
                        f = e & 0xFFFFFFFFFF000
                        if 0x1000 <= f < top:
                            n += 1
                            if n >= need:
                                break
                if n >= need:
                    found.append(pa + base_off * 8)
            pa += 0x10000
        if len(found) >= cap:
            break
    return found


PRIME_BANDS = ((0x400000000, 0x800000000),   # 16-32 GB: every EPROCESS name-hit on
               (0x300000000, 0x400000000))   # this boot lived here (04:2x) - so this
                                             # band is tried before the historic 12-16


def _ordered_ranges(ranges):
    """Prime bands first (in PRIME_BANDS order), the remainder after - a hit never
    waits for a full 27 GB pass."""
    first = []
    for plo, phi in PRIME_BANDS:
        for lo, hi in ranges:
            a, b = max(lo, plo), min(hi, phi)
            if a < b:
                first.append((a, b))
    rest = []
    for lo, hi in ranges:
        cur = lo
        for plo, phi in sorted(PRIME_BANDS):   # subtract the prime spans
            if cur >= hi:
                break
            if plo > cur:
                rest.append((cur, min(plo, hi)))
            cur = max(cur, phi)
        if cur < hi:
            rest.append((cur, hi))
    return first + rest


def discover_peb(g, ram, ranges, pid):
    """Find the CR3 that maps the game's PEB, then read ImageBase from the PEB.

    Self-validating: a wrong frame cannot make PEB+0x10 hold an image base that has
    an 'MZ' under that same frame.  Needs no driver, no DSE, no EPROCESS offset.
    Validated per window so a hit reports immediately instead of after 27 GB.
    """
    peb = _peb_va(pid)
    out("  PEB via NtQueryInformationProcess = %#x" % peb)
    if not peb:
        return None
    t0 = time.perf_counter()

    # Cheap first: frames seen earlier tonight (pool allocations often repeat after a
    # reboot).  Two reads each instead of a 27 GB scan.
    known = (0x34C9EE000, 0x3AD092000, 0x3AD091000, 0x3AD090000)
    for f in known:
        try:
            rd = Reader(g, f)
            raw = rd.read(peb + 0x10, 8)
        except OSError:
            continue
        if not raw:
            continue
        base = struct.unpack("<Q", raw)[0]
        if base and base <= 0x7FFFFFFFFFFF and rd.read(base, 2) == b"MZ":
            size = _image_size_of(rd, base)
            out("  FOUND (known frame) dtb=%#x base=%#x SizeOfImage=%#x (%.1f MB)"
                % (f, base, size, size / 1048576.0))
            return {"dtb": f, "base": base, "size": size}
    out("  known frames did not map the PEB - scanning")

    for wlo, whi in _ordered_ranges(ranges):
        if time.perf_counter() - t0 > 900.0:
            out("    (time cap reached)")
            break
        frames = _scan_frames(g, ram, [(wlo, whi)], cap=250000, need=4)
        out("    window %#012x..%#012x -> %d frames" % (wlo, whi, len(frames)))
        for wi, f in enumerate(frames):
            if wi and wi % 20000 == 0:
                out("      tried %d/%d frames (%.0fs)"
                    % (wi, len(frames), time.perf_counter() - t0))
            try:
                rd = Reader(g, f)
            except OSError:
                continue                      # frame not mappable by this transport
            raw = rd.read(peb + 0x10, 8)      # PEB.ImageBaseAddress
            if not raw:
                continue
            base = struct.unpack("<Q", raw)[0]
            if not base or base > 0x7FFFFFFFFFFF:
                continue
            if rd.read(base, 2) != b"MZ":
                continue
            size = _image_size_of(rd, base)
            out("  FOUND dtb=%#x base=%#x SizeOfImage=%#x (%.1f MB)"
                % (f, base, size, size / 1048576.0))
            return {"dtb": f, "base": base, "size": size}
    out("  no frame mapped the PEB to an MZ image")
    return None


def discover_pml4(g, ram, ranges, want_size=0, cap=60000, max_walk=1500):
    """Find the CR3 whose image matches want_size (0 = take the largest image).

    This is the patch-proof path: a page table is found by shape, its process by the
    image it maps, and nothing depends on an EPROCESS field offset.
    """
    out("  discovering DTB by page-table shape (%d GB pass, ~2-3 min) ..."
        % (sum(b - a for a, b in ranges) // 1073741824))
    cands = _pml4_scan(g, ram, ranges, cap)
    out("    page-table-shaped frames: %d" % len(cands))
    best = None
    walks = 0
    t0 = time.perf_counter()
    for dtb in cands[:max_walk]:
        if time.perf_counter() - t0 > 240.0:
            out("    (walk cap: 240 s)")
            break
        try:
            r = dl.find_mz(g, dtb)
        except OSError:
            continue
        if not r:
            continue
        walks += 1
        va = r[0]
        rd = Reader(g, dtb)
        size = _image_size_of(rd, va)
        if walks <= 6 or (want_size and size == want_size):
            out("    dtb=%#x -> image=%#x size=%#x (%.1f MB)"
                % (dtb, va, size, size / 1048576.0))
        if want_size and size == want_size:
            out("    EXACT match on SizeOfImage=%#x after %d walks" % (size, walks))
            return {"dtb": dtb, "base": va, "size": size}
        if size > 0 and (best is None or size > best["size"]):
            best = {"dtb": dtb, "base": va, "size": size}
    out("    walks that reached a PE: %d" % walks)
    if best:
        out("    best image size=%#x (%.1f MB)" % (best["size"], best["size"] / 1048576.0))
    return best


def _hits_cache(pid):
    return os.path.join(TMP, "qk_hits_%d.txt" % pid)


def _load_hits(pid, max_age=1800):
    """Reuse a recent name sweep: the 80 s scan is the expensive part of iteration."""
    p = _hits_cache(pid)
    if not os.path.exists(p):
        return None
    try:
        if time.time() - os.path.getmtime(p) > max_age:
            return None
        with open(p, "r", encoding="utf-8") as f:
            return [int(x, 16) for x in f.read().split() if x]
    except (OSError, ValueError):
        return None


def _save_hits(pid, hits):
    try:
        with open(_hits_cache(pid), "w", encoding="utf-8") as f:
            f.write("\n".join("%X" % h for h in hits))
    except OSError:
        pass


def _candidate_dtbs(g, hit, ram, lo=0x28, hi=0x800, verbose=False):
    """Walk backwards from a name hit and keep EPROCESS-shaped bases.

    Only two invariants are used, and both are stable across builds:
      * byte at base+0x00  == 3          (KPROCESS dispatcher type, ProcessObject)
      * qword at base+0x28 is a frame    (KPROCESS.DirectoryTableBase)
    ImageFileName has been at 0x338/0x450/0x4C8/0x5A0/0x5A8/0x5B0 across builds,
    so scanning d instead of trusting a constant finds the object either way.
    Reads stay inside the pages around the hit - no arbitrary frame reads.
    """
    pages = {}
    found = []
    seen = set()
    span_lo = (hit - hi - 0x1000) & ~0xFFF
    span_hi = (hit + 8) & ~0xFFF
    for pa in range(span_lo, span_hi + 0x1000, 0x1000):
        if not ram.page_ok(pa):
            continue
        try:
            pages[pa] = g.read_phys(pa, 0x1000)
        except OSError:
            continue

    def at(pa, n):
        page = pa & ~0xFFF
        buf = pages.get(page)
        if buf is None:
            return None
        off = pa & 0xFFF
        if off + n > 0x1000:
            return None
        return buf[off:off + n]

    for d in range(lo, hi):                  # STEP 1, not 8: hits land off the 8-byte
        base = hit - d                       # grid (measured 0x4062f5dfe & 7 == 6), so a
        if base < 0x10000:                   # step-8 scan can never land on the object
            continue                         # base and the type gate never sees the 3.
        tb = at(base, 1)                     # KPROCESS Dispatcher.Header.Type == 3
        if tb is None or tb[0] != 3:
            continue
        db = at(base + 0x28, 8)              # KPROCESS.DirectoryTableBase
        if db is None:
            continue
        dtb = struct.unpack("<Q", db)[0]
        frame = dtb & 0xFFFFFFFFFF000
        if not dtb or dtb >= g.ram_top or not ram.page_ok(frame):
            continue
        if frame in seen:
            continue
        seen.add(frame)
        found.append((base + 0x28, frame, d))
        if verbose and len(found) <= 8:
            tb = at(base, 1)
            out("        d=%#05x base=%#x typebyte=%s dtb=%#x  <-- plausible frame"
                % (d, base, ("%#x" % tb[0]) if tb else "?", dtb))
    return found


def discover(g, pid):
    """DTB + image base: name sweep, then offset-agnostic frame scan + walk.

    No EPROCESS offset is trusted.  The name string locates the object; every
    page-aligned frame in the window is tried as a CR3; find_mz() (a real PE
    check through the page tables) is the only arbiter.
    """
    def _route(s):
        out("    | " + str(s))

    dl.log = _route
    out("  discovering DTB for pid %d (name sweep + frame scan, ~2-3 min) ..." % pid)
    orig_is_ram = g.is_ram
    try:
        ranges, note = dl.usable_ranges(g.ram_top, None, None)
        ram = Ram(ranges)
        out("    ram_top=%#x ranges=%d (%s) usable=%.1f GB"
            % (g.ram_top, len(ranges), note,
               sum(b - a for a, b in ranges) / 1073741824.0))
        # Make dumplive's own is_ram checks as strict as ours for the whole scan:
        # the weak version let an MMIO hole through and the raw read bugchecked
        # the box (21:34).  Every PA read in the walk then hits the real map.
        g.is_ram = ram.page_ok

        # --peb-first: PEB-arbitrated window scan only (reads ~a third of RAM and has
        # never crashed the box), skipping the name sweep entirely on a fresh pid.
        if flag("peb-first"):
            m = discover_peb(g, ram, ranges, pid)
            if m:
                return m
            return discover_pml4(g, ram, ranges, arg("want-size", 0, lambda s: int(s, 0)))

        # Hits first: with the KPROCESS type gate this route is seconds when the hit
        # cache exists and bounded when it does not.  The PEB window scan moved to the
        # fallback slot: its frame-try phase runs into the 420 s cap on a 27.7 GB box
        # (measured 03:3x - a full PEB pass aborted before the name route ever ran).
        hits = None if flag("refresh-hits") else _load_hits(pid)
        if hits:
            out("    hits cache: %d entries (sweep skipped; --refresh-hits to redo)"
                % len(hits))
        else:
            hits, skipped, chunks, rescued = dl.name_hits(g, ranges)
            out("    name hits=%d chunks=%d skipped=%d rescued=%d"
                % (len(hits), chunks, skipped, rescued))
            if hits:
                _save_hits(pid, hits)
        if not hits:
            out("  no ImageFileName hits - wrong game/build, or nothing running")
            return None

        tried = 0
        t0 = time.perf_counter()
        for idx, hit in enumerate(hits[:12]):
            if time.perf_counter() - t0 > 120.0:
                out("    (candidate scan capped at 120 s)")
                break
            if idx < 6:
                out("    hit[%d]=%#x" % (idx, hit))
            cands = _candidate_dtbs(g, hit, ram, verbose=(idx < 6))
            if cands:
                out("    hit=%#x: %d DTB candidate(s) from the EPROCESS header"
                    % (hit, len(cands)))
            for at, dtb, d in cands[:6]:
                tried += 1
                try:
                    r = dl.find_mz(g, dtb)
                except OSError:
                    r = None
                out("      try dtb@%#x=%#x (name_off=%#x) -> %s"
                    % (at, dtb, d, ("MZ@%#x" % r[0]) if r else "no PE"))
                if not r:
                    continue
                out("    (ImageFileName offset for this build = %#x)" % d)
                return {"dtb": dtb, "base": r[0]}
        out("  %d DTBs tried, none walked to an MZ image" % tried)

        # Self-validating fallback: driver-free, offset-free, PEB-arbitrated.
        # 19/11: QK_NO_PEB=1 skips this lane.  Tonight it swept the full 27.7 GB
        # to its 1202 s cap with no verdict while the player sat in a live match;
        # when the EPROCESS header lies, pml4 is the productive last lane.
        if os.environ.get("QK_NO_PEB"):
            out("  (QK_NO_PEB set - skipping PEB window scan)")
        else:
            m = discover_peb(g, ram, ranges, pid)
            if m:
                return m

        # No EPROCESS assumption at all: find the page table by its own shape and
        # identify the process by the image it maps.  Patch-proof by construction.
        want = arg("want-size", 0, lambda s: int(s, 0))
        best = discover_pml4(g, ram, ranges, want)
        if best:
            return best
    except Exception as e:                      # noqa: BLE001
        out("  discovery fault: %s: %s" % (type(e).__name__, e))
    finally:
        g.is_ram = orig_is_ram
    return None


# --------------------------------------------------------------- gdrv3 only
# apexdrv machinery REMOVED 19/11 (policy: strictly gdrv3; a custom mapped
# driver is its own detection surface and mixed-transport sessions produced
# unmeasurable evidence).  The retired code answered DTB/BASE/PHYS IOCTLs on
# \\.\ApexDrv; sources archived to _attic_apexdrv/ (QwenKernPremium) if a
# future, benignly-signed vehicle ever needs the shape back.  Pages gdrv3
# refuses (1450 on some live PML4 frames) are now reported as FAULTED, full
# stop - the discovery routes were tuned around that limit.


def get_map(g, pid):
    """Cached (dtb, base) if it still walks to an MZ, else discover() - gdrv3 only."""
    c = load_cached(pid)
    if c:
        try:
            rd = Reader(g, c["dtb"])
            mz = rd.read(c["base"], 2)
        except OSError:
            mz = None
        if mz == b"MZ":
            out("  dtb cache hit: dtb=0x%X base=0x%X" % (c["dtb"], c["base"]))
            return c
        out("  dtb cache stale (no MZ at cached base) - re-resolving")

    out("  transport: gdrv3 only (no custom driver exists on this path any more)")
    d = discover(g, pid)
    if d:
        save_cache(pid, d["dtb"], d["base"])
    return d


# --------------------------------------------------------------- actions
def hexdump(b, va, n=16):
    rows = []
    for i in range(0, len(b), n):
        chunk = b[i:i + n]
        rows.append("  %#012x  %s  |%s|" % (
            va + i,
            " ".join("%02X" % x for x in chunk).ljust(n * 3 - 1),
            "".join(chr(x) if 32 <= x < 127 else "." for x in chunk)))
    return rows


SETS = {
    "B": {"origin": 0x330, "alive": 0x5DC, "hp": 0x5E0, "shield": 0x5E8,
          "team": 0x10E8, "name": 0x10F0},
    "A": {"origin": 0x258, "health": 0x3A0, "team": 0x478},
}


def decode(rd, ent, idx):
    """Score both candidate field sets on one entity.  Returns (a, b)."""
    buf = rd.read(ent + 0x200, 0x400)
    out("  [%d] ent=%#x" % (idx, ent))
    if buf is None:
        out("        read[0x400@+0x200] FAULT")
        return 0, 0
    s = {0x330: 0, 0x258: 0}
    for tag, base in (("B", 0x200), ("A", 0x200)):
        f = SETS[tag]
        off = f["origin"] - base
        x, y, z = struct.unpack_from("<fff", buf, off)
        if tag == "B":
            alive, hp, sh = struct.unpack_from("<iii", buf, f["alive"] - base)
            out("        B: origin=(%.1f, %.1f, %.1f) alive=%d hp=%d shield=%d"
                % (x, y, z, alive, hp, sh))
            sb = 0
            if all(v == v and abs(v) < 1e6 for v in (x, y, z)) and (x or y or z):
                sb += 2
            if 0 < hp <= 200:
                sb += 2
            if 0 <= sh <= 200:
                sb += 1
            if alive in (0, 1, 2):
                sb += 1
            s["B"] = sb
        else:
            hp = struct.unpack_from("<i", buf, f["health"] - base)[0]
            out("        A: origin=(%.1f, %.1f, %.1f) health=%d" % (x, y, z, hp))
            sa = 0
            if all(v == v and abs(v) < 1e6 for v in (x, y, z)) and (x or y or z):
                sa += 2
            if 0 < hp <= 200:
                sa += 2
            s["A"] = sa
    tail = rd.read(ent + 0x10D8, 0x40)
    if tail is not None:
        team, namep = struct.unpack_from("<iQ", tail, SETS["B"]["team"] - 0x10D8)
        out("        B: team=%d namePtr=%#x" % (team, namep))
        if 0 <= team <= 64:
            s["B"] += 2
        if 0x10000 <= namep <= 0x7FFFFFFFFFFF and (namep & 7) == 0:
            s["B"] += 1
            raw = rd.read(namep, 32)
            if raw:
                txt = "".join(chr(w) for w in struct.unpack_from("<16H", raw)
                              if 32 <= w < 127)
                out("        name: \"%s\"" % (txt or "(non-printable)"))
    out("        score: A=%d B=%d" % (s["A"], s["B"]))
    return s["A"], s["B"]


def act_pe(rd, base):
    mz = rd.read(base, 2)
    out("  base=%#x MZ=%r" % (base, mz))
    if mz != b"MZ":
        return 4
    lf = struct.unpack("<I", rd.read(base + 0x3C, 4))[0]
    hdr = rd.read(base + lf, 0x108)
    if hdr is None:
        return 5
    machine, nsec = struct.unpack_from("<HH", hdr, 4)
    stamp = struct.unpack_from("<I", hdr, 8)[0]
    size = struct.unpack_from("<I", hdr, 0x50)[0]
    out("  PE machine=%#06x sections=%d stamp=%d SizeOfImage=%#x (%.1f MB)"
        % (machine, nsec, stamp, size, size / 1048576.0))

def act_array(rd, va, slots, ents):
    out("  array=%#x slots=%d" % (va, slots))
    found = []
    for i in range(slots):
        v = rd.u64(va + i * 8)
        if v and 0x10000 <= v <= 0x7FFFFFFFFFFF and (v & 7) == 0:
            found.append((i, v))
    out("  canonical slots: %d of %d" % (len(found), slots))
    for i, v in found[:8]:
        out("    slot[%d] = %#x" % (i, v))
    sum_a = sum_b = 0
    n = 0
    for i, v in found[:ents]:
        a, b = decode(rd, v, i)
        sum_a += a
        sum_b += b
        n += 1
    out("  ----")
    out("  decoded=%d scoreA=%d scoreB=%d reads=%d faults=%d"
        % (n, sum_a, sum_b, rd.reads, rd.faults))
    if n == 0:
        out("  RESULT: no-entities")
        out("  VERDICT: PARTIAL - no canonical slots at this address")
        return 8
    if sum_b > sum_a:
        out("  RESULT: setB-leads A=%d B=%d" % (sum_a, sum_b))
        out("  VERDICT: PASS - candidate set B decodes on a live object array (zero attach)")
        return 0
    if sum_a > sum_b:
        out("  RESULT: setA-leads A=%d B=%d" % (sum_a, sum_b))
        out("  VERDICT: PASS - candidate set A decodes on a live object array (zero attach)")
        return 0
    out("  RESULT: ambiguous A=%d B=%d" % (sum_a, sum_b))
    out("  VERDICT: PARTIAL - neither field set decodes cleanly")
    return 9


def act_find_array(rd, base, max_rep=8):
    """Find a static pointer in the image's writable sections that points at an
    array of objects whose first qword (vtable) lives inside the image.

    That is the shape of a live entity array, and the static qword is exactly what
    an 'entity list offset' is.  Everything here is a VA read through the driver's
    physical transport, so no attach and no PA guessing.
    """
    lf = rd.read(base + 0x3C, 4)
    if not lf:
        return 8
    elf = struct.unpack("<I", lf)[0]
    pe = rd.read(base + elf, 0x18)
    if not pe or pe[:4] != b"PE\x00\x00":
        return 8
    nsec = struct.unpack_from("<H", pe, 6)[0]
    optsize = struct.unpack_from("<H", pe, 0x14)[0]
    size_of_image = 0
    oh = rd.read(base + elf + 0x18, 0x60)
    if oh:
        size_of_image = struct.unpack_from("<I", oh, 0x38)[0]
    sec_table = rd.read(base + elf + 0x18 + optsize, nsec * 40)
    if not sec_table:
        return 8
    out("  image SizeOfImage=%#x, %d sections, scanning writable ones" % (size_of_image, nsec))

    reps = []
    scanned = 0
    for i in range(nsec):
        s = sec_table[i * 40:(i + 1) * 40]
        if len(s) < 40:
            break
        name = s[:8].rstrip(b"\x00").decode("ascii", "replace")
        vsize = struct.unpack_from("<I", s, 8)[0]
        vaddr = struct.unpack_from("<I", s, 12)[0]
        chars = struct.unpack_from("<I", s, 36)[0]
        if not (chars & 0x80000000) or vsize == 0:
            continue
        out("    %-8s va=%#x size=%#x (writable)" % (name, vaddr, vsize))
        va = base + vaddr
        end = va + vsize
        cur = va
        while cur + 8 <= end:
            chunk = rd.read(cur, min(0x10000, end - cur))
            if not chunk:
                cur += 0x1000
                continue
            scanned += len(chunk)
            for off in range(0, len(chunk) - 8, 8):
                v = struct.unpack_from("<Q", chunk, off)[0]
                if v < 0x10000 or v > 0x7FFFFFFFFFFF or (v & 7):
                    continue
                slots = rd.read(v, 64)
                if not slots:
                    continue
                cand = [struct.unpack_from("<Q", slots, k * 8)[0] for k in range(8)]
                canon = [c for c in cand if 0x10000 <= c <= 0x7FFFFFFFFFFF and (c & 7) == 0]
                if len(canon) < 4:
                    continue
                vt = 0
                for c in canon[:4]:
                    q = rd.read(c, 8)
                    if q:
                        first = struct.unpack("<Q", q)[0]
                        if base <= first < base + (size_of_image or 0):
                            vt += 1
                if vt >= 3:
                    reps.append((vt, len(canon), cur + off - base, v))
                    if len(reps) > 400:
                        break
            cur += len(chunk)
        if len(reps) > 400:
            break

    out("  scanned %d bytes of writable data, %d array-shaped candidates" % (scanned, len(reps)))
    reps.sort(reverse=True)
    for vt, nc, rva, array_va in reps[:max_rep]:
        out("    STATIC base+%#010x -> array %#x  slots=%d vtable_hits=%d" % (rva, array_va, nc, vt))
    if not reps:
        out("  RESULT: no-array")
        out("  VERDICT: PARTIAL - no vtable-backed pointer array found in writable data")
        return 8
    out("  RESULT: array=%#x static_rva=%#x" % (reps[0][3], reps[0][2]))
    out("  VERDICT: PASS - candidate entity array found; decode with --array=0x%x" % reps[0][3])
    return 0


# ------------------------------------------------------------ --emit feed
# PLAN 1 producer support: one file (temp\qk_feed.json), atomically replaced;
# the overlay's --from-feed is its only consumer.  --fake stays the no-game
# window-draw diagnostic only.
FEED_PATH = os.path.join(TMP, "qk_feed.json")
OFF_FILE_SRC = os.path.join(TMP, "qk_offsets.txt")
SCHEMA = 1
ARRAY_CACHE_TTL = 30.0     # s before a chosen array is re-scanned
SLOT_CAP = 8               # top array slots inspected per frame
MIN_SCORE = 3              # inclusion floor (origin-plausible + hp/shield sane)
# Candidate "set B" field offsets (shapes scored by decode()); RVAs pending
# qk_xref confirmation - offsets are echoed in meta so consumers know the
# provenance of every field they render.
ENT_BUF = 0x200
ENT_FIELDS = {"buf": ENT_BUF, "origin": 0x330, "alive": 0x5DC, "hp": 0x5E0,
              "shield": 0x5E8}
ENT_TAIL_BLOCK = 0x10D8
ENT_TAIL = {"block": ENT_TAIL_BLOCK, "team": 0x10E8, "namePtr": 0x10F0}


def account_stamp():
    """(eaid, banned, srcpath) from _ritual/_account.txt; '?','(missing)' if absent."""
    p = os.path.join(ROOT, "_ritual", "_account.txt")
    eaid = banned = "?"
    try:
        with open(p, "r", encoding="utf-8") as f:
            for ln in f:
                if ln.startswith("ACTIVE_EAID:"):
                    eaid = ln.split(":", 1)[1].strip()
                elif ln.startswith("ACTIVE_BANNED:"):
                    banned = ln.split(":", 1)[1].strip()
        return eaid, banned, p
    except OSError:
        return eaid, banned, "(missing)"


def feed_sources():
    """(vp_rva, fixed_array) persisted by earlier boots in temp\\qk_offsets.txt."""
    vp = arr = None
    try:
        with open(OFF_FILE_SRC, "r", encoding="utf-8") as f:
            for ln in f:
                if ln.startswith("vp_rva="):
                    vp = int(ln.strip().split("=", 1)[1], 16)
                elif ln.startswith("feed_array="):
                    arr = int(ln.strip().split("=", 1)[1], 16)
    except (OSError, ValueError):
        pass
    return vp, arr


def phys_read_bytes(g, pa, n):
    """PA-span read, tolerant of whichever method the gio/gdrv3 object exposes."""
    for name in ("retry_phys", "read_pa", "phys_read", "raw_read"):
        fn = getattr(g, name, None)
        if fn is not None:
            try:
                return fn(pa, n)
            except (TypeError, OSError, AttributeError):
                pass
    try:
        return g.read(pa, n)   # gio readers span physical memory directly
    except (TypeError, OSError, AttributeError):
        return None


def read_matrix_pa(g, image_pa, rva):
    """32-float projection pair at image_pa+rva (check() reads <32f>; leads 0/4)."""
    if image_pa is None or rva is None:
        return None
    b = phys_read_bytes(g, image_pa + rva, 128)
    if b and len(b) == 128:
        return struct.unpack("<32f", b)
    return None


def scan_arrays_lite(rd, base, cap_secs=15.0):
    """Bounded twin of --find-array's writable-section scan; returns sorted reps."""
    try:
        lf = rd.read(base + 0x3C, 4)
        if not lf:
            return []
        elf = struct.unpack("<I", lf)[0]
        pe = rd.read(base + elf, 0x18)
        if not pe or pe[:4] != b"PE\x00\x00":
            return []
        nsec = struct.unpack_from("<H", pe, 6)[0]
        optsize = struct.unpack_from("<H", pe, 0x14)[0]
        soi = 0
        oh = rd.read(base + elf + 0x18, 0x60)
        if oh:
            soi = struct.unpack_from("<I", oh, 0x38)[0]
        st = rd.read(base + elf + 0x18 + optsize, nsec * 40)
        if not st:
            return []
    except OSError:
        return []
    reps = []
    t0 = time.time()
    for i in range(nsec):
        s = st[i * 40:(i + 1) * 40]
        if len(s) < 40:
            break
        vsize = struct.unpack_from("<I", s, 8)[0]
        vaddr = struct.unpack_from("<I", s, 12)[0]
        chars = struct.unpack_from("<I", s, 36)[0]
        if not (chars & 0x80000000) or not vsize:
            continue
        end = base + vaddr + vsize
        cur = base + vaddr
        while cur + 8 <= end and time.time() - t0 < cap_secs:
            chunk = rd.read(cur, min(0x10000, end - cur))
            if not chunk:
                cur += 0x1000
                continue
            for off in range(0, len(chunk) - 8, 8):
                v = struct.unpack_from("<Q", chunk, off)[0]
                if v < 0x10000 or v > 0x7FFFFFFFFFFF or v & 7:
                    continue
                slots = rd.read(v, 64)
                if not slots:
                    continue
                cand = [struct.unpack_from("<Q", slots, k * 8)[0] for k in range(8)]
                canon = [c for c in cand
                         if 0x10000 <= c <= 0x7FFFFFFFFFFF and c & 7 == 0]
                if len(canon) < 4:
                    continue
                vt = 0
                for c in canon[:4]:
                    q = rd.read(c, 8)
                    if q:
                        first = struct.unpack("<Q", q)[0]
                        if base <= first < base + (soi or 0):
                            vt += 1
                if vt >= 3:
                    reps.append((vt, len(canon), cur + off - base, v))
            cur += len(chunk)
            if len(reps) > 200:
                break
        if len(reps) > 200:
            break
    reps.sort(reverse=True)
    return reps


def choose_array(rd, base, override):
    """Array address: --array= override, then the persisted pick, then a capped scan."""
    if override:
        return override
    reps = scan_arrays_lite(rd, base)
    if reps:
        vt, nc, rva, va = reps[0]
        out("  emit array: base+%#010x -> %#x slots=%d vtable_hits=%d" % (rva, va, nc, vt))
        try:
            with open(OFF_FILE_SRC, "a", encoding="utf-8") as f:
                f.write("feed_array=0x%X\n" % va)
        except OSError:
            pass
        return va
    out("  emit array: no candidate this pass")
    return None


def collect_entities(rd, arr_va):
    """Decode the candidate set-B fields off each slot; ents clearing MIN_SCORE."""
    ents = []
    head = rd.read(arr_va, SLOT_CAP * 8)
    if not head:
        return ents, "slot-read-fault"
    slots = struct.unpack_from("<%dQ" % SLOT_CAP, head, 0)
    for k, ptr in enumerate(slots):
        if not (0x10000 <= ptr <= 0x7FFFFFFFFFFF and ptr & 7 == 0):
            continue
        buf = rd.read(ptr + ENT_BUF, 0x400)
        if buf is None:
            continue
        ox, oy, oz = struct.unpack_from("<fff", buf,
                                        ENT_FIELDS["origin"] - ENT_BUF)
        alive, hp, sh = struct.unpack_from("<iii", buf,
                                           ENT_FIELDS["alive"] - ENT_BUF)
        score = 0
        if all(v == v and abs(v) < 1e6 for v in (ox, oy, oz)) and (ox or oy or oz):
            score += 2
        if 0 < hp <= 200:
            score += 2
        if 0 <= sh <= 200:
            score += 1
        if alive in (0, 1, 2):
            score += 1
        if score < MIN_SCORE:
            continue
        ent = {"slot": k, "ptr": ptr, "pos": [ox, oy, oz],
               "alive": alive, "hp": hp, "shield": sh, "score": score}
        tail = rd.read(ptr + ENT_TAIL_BLOCK, 0x40)
        if tail is not None:
            ent["team"] = struct.unpack_from("<i", tail,
                                             ENT_TAIL["team"] - ENT_TAIL_BLOCK)[0]
            ent["name_ptr"] = struct.unpack_from(
                "<Q", tail, ENT_TAIL["namePtr"] - ENT_TAIL_BLOCK)[0]
            # namePtr is a candidate (set-B) POINTER, not a string; deref with
            # the bounded ladder below so live logs carry actual player names.
            # Failure degrades to name_how only - never skips the entity.
            nm, how = resolve_name(rd, ent["name_ptr"])
            if nm:
                ent["name"] = nm
            ent["name_how"] = how
        ents.append(ent)
    return ents, "ok"


def resolve_name(rd, ptr):
    """Deref a candidate namePtr (set-B, unconfirmed) to a printable string.

    Ladder (bounded reads only, never raises):
      a) inline: the bytes AT ptr are a NUL-terminated printable char string;
      b) indirect: *(void**)ptr is itself a pointer to such a string
         (struct {char*; ...} shapes: rhs/CUtlString-alikes).
    Returns (text, how); (None, why) when neither shape fits - the live log
    then still shows name_how=unresolved for that entity instead of silence.
    """
    if not (0x10000 <= ptr <= 0x7FFFFFFFFFFF):
        return None, "bad-ptr"
    raw = rd.read(ptr, 48)
    if raw and len(raw) >= 8:
        s = raw.split(b"\x00", 1)[0]
        if len(s) >= 2 and all(32 <= c < 127 for c in s):
            return s.decode("ascii", "replace"), "inline"
        inner = struct.unpack_from("<Q", raw, 0)[0]
        if 0x10000 <= inner <= 0x7FFFFFFFFFFF and inner != ptr:
            raw2 = rd.read(inner, 48)
            if raw2:
                s2 = raw2.split(b"\x00", 1)[0]
                if len(s2) >= 2 and all(32 <= c < 127 for c in s2):
                    return s2.decode("ascii", "replace"), "indirect"
    return None, "unresolved"


def atomic_write_json(path, rec):
    """Write-then-replace so the overlay never sees a torn frame."""
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(rec, f, separators=(",", ":"))
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def act_emit(rd, g, pid, base, dtb, hz=10.0, secs=300.0):
    """--emit: the producer.  One JSON, atomically replaced, ents+matrix+meta."""
    out("  --emit: schema=%d hz=%.1f secs=%.0f -> %s" % (SCHEMA, hz, secs, FEED_PATH))
    eaid, banned, acct_src = account_stamp()
    out("  account stamp: eaid=%s banned=%s src=%s" % (eaid, banned, acct_src))
    vp_rva, arr_fixed = feed_sources()
    image_pa = None
    try:
        image_pa = rd.page_pa(base)
    except Exception as e:                              # noqa: BLE001
        out("  page_pa failed (%s) - qk_offsets.txt image_pa as fallback"
            % type(e).__name__)
    if image_pa is None:
        try:
            with open(OFF_FILE_SRC, "r", encoding="utf-8") as f:
                for ln in f:
                    if ln.startswith("image_pa="):
                        image_pa = int(ln.strip().split("=", 1)[1], 16)
        except (OSError, ValueError):
            pass
    if vp_rva is None or image_pa is None:
        out("  matrix source incomplete (image_pa=%s vp_rva=%s) - frames carry ents only"
            % (hex(image_pa) if image_pa else None, hex(vp_rva) if vp_rva else None))

    period = 1.0 / hz if hz > 0 else 0.05
    end = time.time() + secs
    frames = fmat = fents = 0
    arr_va = arr_fixed
    arr_age = ARRAY_CACHE_TTL + 1.0      # force a first resolve
    why = "-"
    while time.time() < end:
        tf = time.time()
        if arr_va is None or arr_age > ARRAY_CACHE_TTL:
            arr_va = choose_array(rd, base, arr_fixed)
            arr_age = 0.0
        if arr_va:
            ents, why = collect_entities(rd, arr_va)
        else:
            ents, why = [], "no-array"
        arr_age += period
        mat = None
        if image_pa is not None and vp_rva is not None:
            mat = read_matrix_pa(g, image_pa, vp_rva)
        rec = {
            "schema": SCHEMA,
            "ts": tf,
            "iso": time.strftime("%Y-%m-%d %H:%M:%S"),
            "meta": {
                "producer": "qk_va --emit",
                "pid": pid, "dtb": dtb, "base": base,
                "image_pa": image_pa, "vp_rva": vp_rva, "array": arr_va,
                "transport": "gdrv3", "apexdrv": False,
                "account": {"eaid": eaid, "banned": banned, "src": acct_src},
                "field_offsets": {"fields": ENT_FIELDS, "tail": ENT_TAIL},
                "reads": rd.reads, "faults": rd.faults,
                "ents_reason": why,
            },
            "matrix": list(mat) if mat else None,
            "ents": ents,
        }
        try:
            atomic_write_json(FEED_PATH, rec)
        except OSError as e:
            out("  feed write failed: %s" % e)
        frames += 1
        fmat += 1 if mat else 0
        fents += 1 if ents else 0
        nap = period - (time.time() - tf)
        if nap > 0:
            time.sleep(nap)
    out("  RESULT: emit frames=%d with_matrix=%d with_ents=%d reads=%d faults=%d"
        % (frames, fmat, fents, rd.reads, rd.faults))
    if frames and fmat == frames and fents == frames:
        out("  VERDICT: PASS - feed complete every frame (overlay side: --from-feed)")
        return 0
    if frames:
        out("  VERDICT: PARTIAL - %d frame(s), matrix=%d/%d ents=%d/%d (last reason=%s)"
            % (frames, fmat, frames, fents, frames, why))
        return 6
    out("  VERDICT: FAIL - no frame fitted into secs=%.0f" % secs)
    return 5


# --------------------------------------------------------------- stage 1b watch
def act_watch(rd, at, secs, pid):
    out("  Stage 1b gate: %ds of 1 Hz zero-attach reads at %#x" % (secs, at))
    t0 = time.perf_counter()
    n = good = 0
    died = False
    while time.perf_counter() - t0 < secs:
        b = rd.read(at, 4)
        n += 1
        if b is not None:
            good += 1
        alive = 1
        try:
            alive = 1 if dl.pid_alive(pid) else 0
        except Exception:                       # noqa: BLE001
            alive = -1
        out("  T+%02ds read=%s pid_alive=%d reads=%d faults=%d"
            % (int(time.perf_counter() - t0), (b.hex() if b is not None else "FAULT"),
               alive, rd.reads, rd.faults))
        if alive == 0:
            died = True
            out("  target died at T+%ds (check the Application log for Javelin 1000)"
                % int(time.perf_counter() - t0))
            break
        time.sleep(max(0.05, 1.0 - ((time.perf_counter() - t0) % 1.0)))
    el = int(time.perf_counter() - t0)
    out("  ALIVE reads=%d ok=%d elapsed=%ds" % (n, good, el))
    out("  RESULT: watch good=%d/%d reads=%d faults=%d" % (good, n, rd.reads, rd.faults))
    # A death is never a PASS, even when every read succeeded (R9).
    if died:
        out("  VERDICT: FAIL - target died at T+%ds after %d clean zero-attach reads; "
            "the transport worked, the game did not survive" % (el, good))
        return 1
    if good == n and n > 0:
        out("  VERDICT: PASS - %ds of zero-attach reads, target alive; now confirm the "
            "Application log has NO 'EA Javelin Anticheat' 1000 in this window" % el)
        return 0
    out("  VERDICT: PARTIAL - %d of %d reads faulted" % (n - good, n))
    return 5


# --------------------------------------------------------------- main
def main():
    out_path = arg("out", os.path.join(TMP, "qk_va_%s.txt" % time.strftime("%Y%m%d_%H%M%S")))
    set_out(out_path)

    if not dl.elevation() and not flag("no-elevate"):
        # ABSOLUTE script path: run_elevated() starts the child in ext\, so a
        # relative "ext\qk_va.py" would resolve to ext\ext\qk_va.py and die
        # silently before writing anything (measured: 4 runs, 0 files).
        argv = [os.path.abspath(sys.argv[0])] + [a for a in sys.argv[1:] if a != "--no-elevate"]
        if not any(a.startswith("--out") for a in argv):
            argv.append("--out=" + OUT_PATH)
        cmd = " ".join('"%s"' % a if " " in a else a for a in argv)
        out("not elevated - relaunching elevated (the gdrv3 device DACL needs it)")
        res = dl.run_elevated(cmd)
        out(res)
        return 0

    out("===== qk_va v1 (zero-attach VA read: gdrv3 physical + own page walk) =====")
    out("out=%s" % out_path)

    # --name: override ImageFileName so the pipeline can be tested on any process
    # (the game is not always running; a wrong discovery costs a game session).
    nm = arg("name", "")
    if nm:
        dl.NAME = nm.encode("ascii", "ignore")[:14] + b"\x00"
        out("image-name override: %r (ImageFileName[15])" % dl.NAME)

    try:
        g = gio.Gio()
    except OSError as e:
        out("gio open failed: %s (gdrv3 not running, or not elevated)" % e)
        out("VERDICT: PARTIAL - no transport")
        flush(out_path)
        return 2

    rc = 0
    try:
        pid = arg("pid", 0, lambda s: int(s, 0)) or 0
        if not pid:
            try:
                pid = int(dl.find_pid() or 0)
            except Exception:                   # noqa: BLE001
                pid = 0
        if not pid:
            out("no r5apex process and no --pid")
            out("VERDICT: PARTIAL - target absent")
            return 3
        out("target pid=%d" % pid)

        m = get_map(g, pid)
        if not m:
            out("RESULT: no-dtb")
            out("VERDICT: FAIL - page tables not resolved (the pid scan output above says why)")
            return 4
        rd = Reader(g, m["dtb"])
        base = m["base"]

        if flag("no-driver"):
            out("--no-driver: accepted, no-op (gdrv3-only is unconditional; apexdrv removed)")
        if flag("emit"):
            rc = act_emit(rd, g, pid, base, m["dtb"],
                          hz=arg("hz", 10, lambda s: float(s)),
                          secs=arg("secs", 300, lambda s: float(s)))
        elif flag("pe"):
            rc = act_pe(rd, base)
        elif flag("find-array"):
            rc = act_find_array(rd, base)
        elif arg("array", 0, lambda s: int(s, 0)):
            rc = act_array(rd, arg("array", 0, lambda s: int(s, 0)),
                           arg("slots", 64, lambda s: int(s, 0)),
                           arg("ents", 4, lambda s: int(s, 0)))
        elif arg("watch", 0, lambda s: int(s, 0)):
            rc = act_watch(rd, arg("at", base, lambda s: int(s, 0)),
                           arg("watch", 0, lambda s: int(s, 0)), pid)
        else:
            at = arg("at", base, lambda s: int(s, 0))
            ln = arg("len", 64, lambda s: int(s, 0))
            b = rd.read(at, ln)
            if b is None:
                out("  RESULT: fault at %#x" % at)
                out("  VERDICT: FAIL - page not present through the walk")
                rc = 5
            else:
                out("  read %d bytes at %#x" % (len(b), at))
                for row in hexdump(b, at):
                    out(row)
                out("  RESULT: ok reads=%d faults=%d" % (rd.reads, rd.faults))
                out("  VERDICT: PASS - zero-attach VA read")
    finally:
        try:
            g.close()
        except Exception:                       # noqa: BLE001
            pass
        flush(out_path)
    return rc


if __name__ == "__main__":
    sys.exit(main())


