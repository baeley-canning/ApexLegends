r"""qk_va.py -- ZERO-ATTACH virtual-address reader (PLAN stage 1b / 2).

WHY THIS EXISTS
    apexdrv reads do one KeStackAttachProcess per IOCTL.  On 07/11 that was
    followed by EAAC terminating the game twice (ExitType 0x322327458D1ED790,
    14 s and ~4 min after the read bursts).  gdrv3 has swept 9 GB of physical
    memory with ZERO Javelin events, and its read path (MmMapIoSpace in the
    caller's own context) never attaches to the game's address space.

    So: read physically, walk the page tables ourselves, and the only kernel
    footprint is the resident gdrv3 image.  That is the shape with evidence of
    survival, and it is the Stage 1b gate: 10 minutes of 1 Hz reads with no
    Javelin event.

DTB
    Cached in temp\qk_dtb_<pid>.txt together with the image base, so only the
    first run of a game session pays the discovery (~70-80 s via p72_ppath's
    pid scan).  A new game process => new pid => fresh discovery.

USAGE
    python ext\qk_va.py --pe                     # image base + MZ + sections
    python ext\qk_va.py --at=0x7FF721690000 --len=64
    python ext\qk_va.py --array=0xB675E68 --slots=64     # pointer array -> entities
    python ext\qk_va.py --watch=600 --at=<base>          # Stage 1b survival gate

EXIT   0 ok | 2 no driver | 3 no game | 4 no dtb | 5 read failed
"""
import bisect
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
                b = self.g.read_phys(pa + off, take)
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


def _pml4_scan(g, ram, ranges, cap=4096):
    """Every 4 KiB page in RAM that looks like a page table (>=8 RAM-backed present entries).

    Reads 64 KiB at a time: one pass over 27.7 GB is ~150 s, versus ~8M 4 KiB ioctls.
    No EPROCESS offset is involved anywhere - a PML4 is recognised by its own shape.
    """
    found = []
    for rlo, rhi in ranges:
        pa = (rlo + 0xFFF) & ~0xFFF
        while pa + 0x10000 <= rhi and len(found) < cap:
            try:
                blk = g.read_phys(pa, 0x10000)
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


def discover_pml4(g, ram, ranges, want_size=0, cap=4096, max_walk=400):
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

    for d in range(lo, hi, 8):
        base = hit - d
        if base < 0x10000:
            continue
        db = at(base + 0x28, 8)
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


# apexdrv v15: exact DTB and image base, one IOCTL each.  0x8A702020 = CTL_CODE(0x8A70,0x808),
# 0x8A70201C = CTL_CODE(0x8A70,0x807).  Both structs are {pid,res,status,src/base/dtb} = 24 B.
APEXDRV_PATH = r"\\.\ApexDrv"
IOCTL_DRV_DTB = 0x8A702020
IOCTL_DRV_BASE = 0x8A70201C


IOCTL_DRV_PHYS = 0x8A702024   # CTL_CODE(0x8A70, 0x809)

_k32 = None
_drv = None


def _drv_handle():
    """One cached handle: the name sweep issues ~500k reads, so no CreateFile per call."""
    global _k32, _drv
    if _drv is not None:
        return _drv
    import ctypes
    from ctypes import wintypes
    if _k32 is None:
        _k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        _k32.CreateFileW.restype = ctypes.c_void_p
        _k32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                      ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD,
                                      ctypes.c_void_p]
    h = _k32.CreateFileW(APEXDRV_PATH, 0xC0000000, 0, None, 3, 0, None)
    if not h or h == ctypes.c_void_p(-1).value:
        return None
    _drv = h
    return _drv


def drv_phys(pa, n):
    """Read n bytes at physical pa through apexdrv (MmCopyMemory PHYSICAL).

    Drop-in replacement for gio.read_phys: same (pa, size) contract, OSError on
    failure.  No MmMapIoSpace and no attach, so an unbacked page is a status, not
    a bugcheck - and gdrv3's 1450 on some page-table frames does not apply.
    """
    import ctypes
    from ctypes import wintypes
    if n < 1 or n > 0x1000:
        raise OSError(22, "drv_phys size %d" % n)
    h = _drv_handle()
    if not h:
        raise OSError(6, "no ApexDrv handle")
    size = 24 + 0x1000
    buf = ctypes.create_string_buffer(size)
    struct.pack_into("<QII", buf, 0, pa, n, 0)
    ret = wintypes.DWORD(0)
    ok = _k32.DeviceIoControl(ctypes.c_void_p(h), wintypes.DWORD(IOCTL_DRV_PHYS), buf,
                               wintypes.DWORD(size), buf, wintypes.DWORD(size),
                               ctypes.byref(ret), None)
    if not ok:
        raise OSError(ctypes.get_last_error(), "drv_phys %#x+%#x ioctl failed" % (pa, n))
    status, copied = struct.unpack_from("<iI", buf, 16)
    if status != 0:
        raise OSError(status & 0xFFFFFFFF, "drv_phys %#x+%#x status %#x" % (pa, n, status))
    return bytes(buf.raw[24:24 + n])


def _drv_call24(code, payload):
    """A 24-byte request/response IOCTL (DTB / BASE) on the cached handle."""
    import ctypes
    from ctypes import wintypes
    h = _drv_handle()
    if not h:
        return None
    buf = ctypes.create_string_buffer(24)
    ctypes.memmove(buf, payload, 24)
    ret = wintypes.DWORD(0)
    ok = _k32.DeviceIoControl(ctypes.c_void_p(h), wintypes.DWORD(code), buf,
                               wintypes.DWORD(24), buf, wintypes.DWORD(24),
                               ctypes.byref(ret), None)
    return buf.raw if ok else None


def map_from_driver(pid):
    """(dtb, base) straight from apexdrv - exact, no scan, no page-table guessing."""
    empty = struct.pack("<IIiIQ", pid, 0, 0, 0, 0)
    d = _drv_call24(IOCTL_DRV_DTB, empty)
    if not d:
        out("  driver: no handle (ApexDrv not loaded?)")
        return None
    status, valid, dtb = struct.unpack_from("<iIQ", d, 8)
    out("  driver DTB: status=%#x valid=%d dtb=%#x" % (status & 0xFFFFFFFF, valid, dtb))
    if not valid or not dtb:
        return None
    b = _drv_call24(IOCTL_DRV_BASE, empty)
    base = 0
    if b:
        bstatus, bsrc, v = struct.unpack_from("<iIQ", b, 8)
        out("  driver BASE: status=%#x source=%d base=%#x" % (bstatus & 0xFFFFFFFF, bsrc, v))
        base = v
    return {"dtb": dtb, "base": base}


def get_map(g, pid):
    """cached (dtb, base) if it still walks to an MZ, else ask the driver, else discover."""
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

    # The driver answers in microseconds and cannot be wrong about its own process.
    try:
        m = None if flag("no-driver") else map_from_driver(pid)
    except Exception as e:                      # noqa: BLE001
        out("  driver path fault: %s: %s" % (type(e).__name__, e))
        m = None
    if m and m["base"]:
        # Switch the transport BEFORE walking: the driver's MmCopyMemory PHYSICAL
        # has the same (pa,size) contract as gio.read_phys, but it can read pages
        # gdrv3 fails on (Errno 1450 on a PML4 frame) and never attaches.
        try:
            g.read_phys = drv_phys
            rd = Reader(g, m["dtb"])
            ok = (rd.read(m["base"], 2) == b"MZ")
        except OSError as e:
            out("  driver transport walk failed: %s" % e)
            ok = False
        if ok:
            save_cache(pid, m["dtb"], m["base"])
            out("  driver map verified: MZ at base via MmCopyMemory; cache written")
            return m
        out("  driver map did not verify (no MZ at base) - falling back")

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


# --------------------------------------------------------------- stage 1b watch
def act_watch(rd, at, secs, pid):
    out("  Stage 1b gate: %ds of 1 Hz zero-attach reads at %#x" % (secs, at))
    t0 = time.perf_counter()
    n = good = 0
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
            out("  target died at T+%ds (check the Application log for Javelin 1000)"
                % int(time.perf_counter() - t0))
            break
        time.sleep(max(0.05, 1.0 - ((time.perf_counter() - t0) % 1.0)))
    el = int(time.perf_counter() - t0)
    out("  ALIVE reads=%d ok=%d elapsed=%ds" % (n, good, el))
    out("  RESULT: watch good=%d/%d reads=%d faults=%d" % (good, n, rd.reads, rd.faults))
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

        if flag("pe"):
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


