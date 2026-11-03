r"""dumplive.py -- dump the live r5apex_dx12 image through gdrv3 physical reads.

p40d (track A).  PURE READ probe: no driver load, no DSE write, no service
touch, no writable mapping -- everything goes through 0xC3502014, so there is
no pre-state to restore beyond closing the handle.

Method
  1. scan physical RAM (skip VGA hole and the 3-4 GiB PCI hole) for the pool
     copy of EPROCESS.ImageFileName == "r5apex_dx12.exe", gate the containing
     page on UniqueProcessId == pid, derive EPROCESS base from the object
     header shift, read DirectoryTableBase (+0x28)
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
import sys
import time
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "_ritual", "p40d_livedump.txt")
NAME = b"r5apex_dx12.exe\x00"
PROC_NAME = "r5apex_dx12"

SCAN_LO = 0x100000
SCAN_CHUNK = 0x10000            # ioctl dst is allocated for this; dump lowers it
HOLES = [(0x000A0000, 0x00100000),      # VGA/ROM
         (0xC0000000, 0x100000000)]     # PCI/MMIO space
HIT_CAP = 96
PTE_CAP = 6000000
SHIFTS = range(0x10, 0x78, 8)          # OBJECT_HEADER + pool padding variants
PID_OFFS = (0x430, 0x438, 0x440, 0x448, 0x450, 0x458, 0x460, 0x468,
            0x470, 0x478, 0x480)
MASK = 0x000FFFFFFFFFF000
MIN_IMAGE = 0x4000000
MAX_IMAGE = 0xC0000000

LOG = []


def log(s):
    LOG.append(s)
    print(s)


kernel32 = gio.kernel32
shell32 = ctypes.WinDLL("shell32", use_last_error=True)
advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)


# ---------------------------------------------------------------- elevation
def elevation():
    tok = wintypes.HANDLE()
    advapi32.OpenProcessToken(kernel32.GetCurrentProcess(), 0x0008,
                              ctypes.byref(tok))
    rl = wintypes.DWORD(0)
    advapi32.GetTokenInformation(tok, 20, ctypes.byref(rl), 4,
                                 ctypes.byref(rl))
    kernel32.CloseHandle(tok)
    return rl.value


class SHELLEXECUTEINFOW(ctypes.Structure):
    _fields_ = [("cbSize", wintypes.DWORD), ("fMask", wintypes.ULONG),
                ("hwnd", wintypes.HWND), ("lpVerb", wintypes.LPCWSTR),
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
def scan_ranges(ram_top):
    top = min(ram_top, 0x4000000000) if ram_top else 0x100000000
    ranges = []
    cur = SCAN_LO
    for lo, hi in sorted(HOLES):
        if hi <= cur:
            continue
        if lo >= top:
            break
        if lo > cur:
            ranges.append((cur, min(lo, top)))
        cur = max(cur, hi)
        if cur >= top:
            break
    if cur < top:
        ranges.append((cur, top))
    return ranges


def name_hits(g, ram_top, chunk=SCAN_CHUNK, cap=HIT_CAP):
    """Physical addresses of the NAME string; faults skip one chunk.
    A 15-byte carry covers hits straddling chunk boundaries."""
    hits = []
    skipped = 0
    chunks = 0
    for lo, hi in scan_ranges(ram_top):
        pa = lo
        carry = b""
        while pa < hi and len(hits) < cap:
            n = min(chunk, hi - pa)
            try:
                blk = g.read_phys(pa, n)
            except OSError:
                skipped += 1
                chunks += 1
                pa += chunk
                carry = b""
                continue
            chunks += 1
            buf2 = carry + blk
            base = pa - len(carry)
            off = 0
            while len(hits) < cap:
                i = buf2.find(NAME, off)
                if i < 0:
                    break
                hits.append(base + i)
                off = i + 1
            carry = blk[-15:]
            pa += n
    return hits, skipped, chunks


def valid_cr3(g, dtb):
    return (dtb and not (dtb & 0xFFF) and dtb < g.ram_top and g.is_ram(dtb))


def candidates_for(g, pid, hits):
    """Dedupe cr3 candidates: name page -> shift -> pid dword -> DTB."""
    out = []
    seen = set()
    for page in dict.fromkeys(h & ~0xFFF for h in hits):
        try:
            p = g.read_phys(page, 0x2000)      # page + successor (header+pid)
        except OSError:
            continue
        off = next(h for h in hits if (h & ~0xFFF) == page) - page
        for s in SHIFTS:
            b = off + s
            if b + 0x488 > len(p):
                continue
            if not any(struct.unpack_from("<I", p, b + o)[0] == pid
                       for o in PID_OFFS):
                continue
            dtb = struct.unpack_from("<Q", p, b + 0x28)[0]
            if not valid_cr3(g, dtb):
                log("  cand page=%#x shift=%#x pid-ok dtb=%#x (reject)"
                    % (page, s, dtb))
                continue
            key = (page, s)
            if key in seen:
                continue
            seen.add(key)
            out.append((page + s, dtb))
    if not out:
        log("  %d hit pages, none passed the pid gate" % len(hits))
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


class Walk(object):
    """CR3 -> VA page resolution; PD pages cached, every PA is_ram-checked."""

    def __init__(self, g, cr3):
        self.g = g
        self.cr3 = cr3
        self.pdpt_pa = 0
        self.cache = {}
        pm = g.read_phys(cr3, 0x1000)          # PML4
        e0 = u64(pm, 0)
        if e0 & 1:
            p = e0 & MASK
            if g.is_ram(p):
                self.pdpt_pa = p

    def pt_for(self, va):
        if not self.pdpt_pa:
            return None
        ii = (va >> 30) & 0x1FF
        jj = (va >> 21) & 0x1FF
        key = (ii, jj)
        if key in self.cache:
            return self.cache[key]
        res = None
        try:
            e = self.g.u64(self.pdpt_pa + ii * 8)
            if (e & 1) and not (e & 0x80):
                pd_pa = e & MASK
                if self.g.is_ram(pd_pa):
                    pd = self.g.read_phys(pd_pa, 0x1000)
                    d = u64(pd, jj * 8)
                    if (d & 1) and not (d & 0x80):
                        pt_pa = d & MASK
                        if self.g.is_ram(pt_pa):
                            res = self.g.read_phys(pt_pa, 0x1000)
        except OSError:
            res = None
        self.cache[key] = res
        return res

    def page_pa(self, va):
        pt = self.pt_for(va)
        if pt is None:
            return None
        pte = u64(pt, ((va >> 12) & 0x1FF) * 8)
        if not (pte & 1):
            return None
        pa = pte & MASK
        return pa if self.g.is_ram(pa) else None


def find_mz(g, cr3):
    """First page in PML4[0] that passes validate_pe; returns (va, meta)."""
    w = Walk(g, cr3)
    if not w.pdpt_pa:
        return None
    probe = 0
    try:
        pdpt = g.read_phys(w.pdpt_pa, 0x1000)
    except OSError:
        return None
    for ii in range(256):                       # user VA stays below 512 GiB
        e = u64(pdpt, ii * 8)
        if not (e & 1) or (e & 0x80):
            continue
        pd_pa = e & MASK
        if not g.is_ram(pd_pa):
            continue
        try:
            pd = g.read_phys(pd_pa, 0x1000)
        except OSError:
            continue
        for jj in range(512):
            d = u64(pd, jj * 8)
            if not (d & 1):
                continue
            if d & 0x80:                        # 2 MiB page: probe page 0 only
                base_va = (ii << 30) | (jj << 21)
                pa = d & MASK
                probe += 1
                if base_va >= 0x10000 and g.is_ram(pa):
                    try:
                        if g.read_phys(pa, 2) == b"MZ":
                            meta = validate_pe(g.read_phys(pa, 0x1000))
                            if meta:
                                return base_va, meta
                    except OSError:
                        pass
                continue
            pt_pa = d & MASK
            if not g.is_ram(pt_pa):
                continue
            try:
                pt = g.read_phys(pt_pa, 0x1000)
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
                    if g.read_phys(pa, 2) != b"MZ":
                        continue
                    meta = validate_pe(g.read_phys(pa, 0x1000))
                except OSError:
                    continue
                if meta:
                    return ((ii << 30) | (jj << 21) | (kk << 12)), meta
    return None


# ---------------------------------------------------------------- dump
class Stats(object):
    def __init__(self):
        self.read = 0
        self.zero = 0
        self.fail = 0


def flush_run(g, buf, va, pa, n, st):
    try:
        buf[va:va + n] = g.read_phys(pa, n)
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
        g = gio.Gio(chunk=SCAN_CHUNK)
    except OSError as e:
        log("FATAL: %s" % e)
        return _finish(1, "FATAL no transport")
    log("PRE ram_top=%#x installed=%d MiB" % (g.ram_top, g.ram_top // 0x100000))

    hits, skipped, chunks = name_hits(g, g.ram_top)
    log("scan: %d hits, %d/%d chunks faulted at %#x, %.1f s"
        % (len(hits), skipped, chunks, SCAN_CHUNK, time.perf_counter() - _T0))
    if not hits and skipped:
        log("retry scan at %#x chunks" % PAGE)
        g.chunk = PAGE
        hits, skipped, chunks = name_hits(g, g.ram_top, chunk=PAGE)
        log("retry: %d hits, %d/%d chunks faulted, %.1f s"
            % (len(hits), skipped, chunks, time.perf_counter() - _T0))
    for h in hits:
        log("  hit %#x" % h)
    if not hits:
        g.close()
        return _finish(2, "NO_HITS")

    cands = candidates_for(g, pid, hits)
    log("candidates: %d" % len(cands))
    for base, dtb in cands:
        log("  eprocess=%#x dtb=%#x" % (base, dtb))
    if not cands:
        g.close()
        return _finish(3, "NO_CR3")

    found = None
    for base, dtb in cands:
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


def main():
    pid = None
    for a in sys.argv:
        if a.startswith("--pid="):
            pid = int(a.split("=", 1)[1])
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
    if elevation() == 1 or "--elevated" in sys.argv:
        return elevated_main(pid)
    params = '"%s" --elevated --pid=%d' % (os.path.abspath(sys.argv[0]), pid)
    try:
        os.remove(OUT)
    except OSError:
        pass
    print("parent: elevating for pid=%d" % pid)
    print(run_elevated(params))
    if os.path.exists(OUT):
        print("--- %s" % OUT)
        print(open(OUT, encoding="utf-8").read())
    return 0


_T0 = time.perf_counter()
if __name__ == "__main__":
    sys.exit(main())


