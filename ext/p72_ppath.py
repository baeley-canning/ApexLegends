r"""p72_ppath.py -- static pointer chain from r5apex_dx12 into a watched TADDR.

Stage `map`
  Reuse the dumplive front half byte for byte: pid -> EPROCESS (name + pid +
  26200 shape + DTB), walk the DTB for the MZ page whose SizeOfImage is
  > 64 MiB, take that as the image base, and dump ONE module section (.data
  first, .rdata only on request) to temp\p72_data.bin.  Nothing is written to
  the game; the only handle is the gdrv3 device.

Stage `chain`
  BFS over the dumped section: every 8-aligned qword that is a canonical user
  VA whose leaf page is PRESENT through the same page tables is a pointer.
  Stops a branch when the resolved physical page equals the watched target
  page -- the landing is exact in PA space, so no reverse page-table walk and
  no PA compare heuristics are needed.  Surviving chains are re-walked from
  scratch against live memory (R3: the read-back is the verdict) and the
  floats at the landing are printed next to what p71 saw churn.

Why PFN compare and not "does it point at the struct": a page-table walk says
*where* a pointer lands, to the byte.  Address-space layout ASLR is irrelevant
to the chain (module base + offsets), and a hit that lands pages away is
visibly off instead of a scored guess.

Usage
  python ext\p72_ppath.py --stage=map --pid=12092 --target=0x420b0a000
  python ext\p72_ppath.py --stage=chain [--depth=4] [--nodes=250000]
         [--branch=24] [--maxsec=0x4000000] [--sec=.rdata]

Guards: pid alive both ends, target page is_ram, base < 0x800000000000, every
table and leaf PA is_ram-checked, branch and node caps, depth cap, section cap,
per-hit re-walk, and the map file is keyed to the pid + target so a stale map
cannot be applied to a restarted game.
"""
import ctypes
import hashlib
import os
import struct
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
# dumplive bakes OUT/PROG at import; name them before the import (R5: p72 has
# its own output file, the p40d defaults stay untouched for older recipes).
os.environ.setdefault("DUMP_OUT", "p72_out.txt")
os.environ.setdefault("DUMP_PROG", "p72_prog.txt")
import gio  # noqa: E402
import dumplive as dl  # noqa: E402

ROOT = os.path.dirname(HERE)
# dumplive hardcodes _ritual\ for OUT/PROG; p72 keeps its artifacts in temp\
# next to its data and map file (R5: own number, own output).
OUT = os.path.join(ROOT, "temp", os.environ.get("DUMP_OUT", "p72_out.txt"))
PROG = os.path.join(ROOT, "temp", os.environ.get("DUMP_PROG", "p72_prog.txt"))
dl.OUT = OUT
dl.PROG = PROG
MAP = os.path.join(ROOT, "temp", "p72_map.txt")
DATA = os.path.join(ROOT, "temp", "p72_data.bin")

PAGE = 0x1000
CANON_LO = 0x10000
CANON_HI = 0x800000000000      # user half only; 0xffff.. kernel VAs are rare
                               # in a game's .data and cost a wasted walk
SECCAP_DEF = 0x4000000         # 64 MiB per section, ~16k pages
DEPTH_DEF = 4                  # 5 derefs: module -> .. -> struct
NODES_DEF = 250000
BRANCH_DEF = 24                # pointers followed per page, evenly sampled
HITCAP = 200
PAGECACHE = 20000              # pages held in RAM; 80 MiB, cleared when full

OPT = {"stage": "map", "pid": 0, "target": 0, "depth": DEPTH_DEF,
       "nodes": NODES_DEF, "branch": BRANCH_DEF, "maxsec": SECCAP_DEF,
       "sec": ".data", "inplace": False, "want": 0x0, "dtb": 0, "base": 0,
       "front": "both", "lo": 0, "hi": 0}

log = dl.log
prog = dl.prog


def canon(q):
    """Aligned user-space VA in the canonical lower half."""
    return CANON_LO <= q < CANON_HI and not (q & 7)


def sample(vals, k):
    """Evenly spread at most k entries -- taking the first k would always
    follow the head of the page and starve the rest."""
    if len(vals) <= k:
        return vals
    step = len(vals) / float(k)
    return [vals[int(i * step)] for i in range(k)]


# ---------------------------------------------------------------- map file
def write_map(fields):
    os.makedirs(os.path.dirname(MAP), exist_ok=True)
    with open(MAP, "w", encoding="utf-8") as f:
        for k, v in fields:
            f.write("%s=%s\n" % (k, v))


def read_map():
    d = {}
    with open(MAP, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and "=" in line:
                k, v = line.split("=", 1)
                d[k] = v
    return d



# ---------------------------------------------------------------- stage map
def front_half(g, pid):
    """Name scan -> EPROCESS gate -> DTB -> PE page.  -> (base, meta, dtb)."""
    if OPT["dtb"]:
        # A faulted walk must not cost another 72 s scan: the EPROCESS/DTB do
        # not change while the pid lives, so the operator can feed it back in.
        log("REUSE dtb=%#x (scan skipped, gated by valid_cr3)" % OPT["dtb"])
        cands = [(99, 0, OPT["dtb"])] if dl.valid_cr3(g, OPT["dtb"]) else []
    else:
        ranges, note = dl.usable_ranges(g.ram_top)
        total = sum(b - a for a, b in ranges)
        log("RAMMAP %s ranges=%d total=%d MiB" % (note, len(ranges), total >> 20))
        prog("RAMMAP %s ranges=%d total=%d MiB" % (note, len(ranges), total >> 20))
        if not ranges:
            return None
        hits, skipped, chunks, rescued = dl.name_hits(g, ranges)
        log("scan: %d hits, %d/%d chunks faulted, %d pages rescued, %.1f s"
            % (len(hits), skipped, chunks, rescued, time.perf_counter() - dl._T0))
        if not hits:
            return None
        for h in hits:
            log("  hit %#x" % h)
        cands = dl.candidates_for(g, pid, hits)
        if not cands:
            # A live EPROCESS can drift out of the scoring shape; readability
            # of the frame (checked by the caller) is the stronger filter, so
            # widen rather than declare NO_BASE.
            log("gate empty at MIN_SCORE=%d -> retry at 4" % dl.MIN_SCORE)
            dl.MIN_SCORE = 4
            cands = dl.candidates_for(g, pid, hits)
    log("candidates: %d" % len(cands))
    for score, base, dtb in cands[:8]:
        log("  eprocess=%#x dtb=%#x score=%d" % (base, dtb, score))
    # The frame must be READABLE for a walk to mean anything, and 1450 is
    # known to hit specific pages (p43z / p44b) -- often only the wrong
    # candidate's.  Readability therefore outranks score: walk every
    # candidate, keep the first that yields a PE page.
    for score, base, dtb in cands[:12]:
        frame = dtb & dl.MASK
        r = None
        for attempt in range(4):
            try:
                dl.retry_phys(g, frame, PAGE)
            except OSError as e:
                log("  frame %#x unreadable try=%d %s"
                    % (frame, attempt + 1, e))
                time.sleep(0.4 * (attempt + 1))
                continue
            log("  frame %#x readable (cand dtb=%#x score=%d)"
                % (frame, dtb, score))
            try:
                r = dl.find_mz(g, dtb)
            except OSError as e:
                # Table pages can fault mid-walk even when the PML4 did not.
                log("  walk dtb=%#x fault try=%d %s" % (dtb, attempt + 1, e))
                time.sleep(0.25 * (attempt + 1))
                continue
            break
        if r:
            log("  walk dtb=%#x -> image va=%#x secs=%d"
                % (dtb, r[0], len(r[1]["secs"])))
            try:
                peb = struct.unpack("<Q", dl.retry_phys(
                    g, (base + dl.OFF_PEB) & ~0xFFF, PAGE)[dl.OFF_PEB & 0xFFF:][:8])[0]
                log("  eprocess %#x peb=%#x links=%#x/%#x"
                    % (base, peb,
                       struct.unpack("<Q", dl.retry_phys(
                           g, (base + dl.LINK_OFF) & ~0xFFF, PAGE)[dl.LINK_OFF & 0xFFF:][:8])[0],
                       struct.unpack("<Q", dl.retry_phys(
                           g, (base + dl.LINK_OFF + 8) & ~0xFFF, PAGE)[(dl.LINK_OFF + 8) & 0xFFF:][:8])[0]))
            except OSError as e:
                log("  shape reread fault %s" % e)
            return r[0], r[1], dtb
        if r is None:
            log("  walk dtb=%#x -> gave up after 4 faulted attempts" % dtb)
            continue
        try:
            log("  walk dtb=%#x -> no PE (%s)" % (dtb, dl.probe_dtb(g, dtb)))
        except OSError as e:
            log("  walk dtb=%#x -> no PE (probe fault %s)" % (dtb, e))
    return None


def section(meta, name):
    for sname, va, vsize in meta["secs"]:
        if sname == name:
            return va, vsize
    return None


def dump_section(g, w, buf, va0, size, st):
    """Copy [va0, va0+size) into buf at index 0, present pages only.

    dumplive.dump_range indexes the buffer with the VA, which relies on
    bytearray clamping the write to the end -- true for a whole-image dump
    (headers, then sections, in VA order), wrong for one section at a high
    VA: the first page would land at index len(buf), not 0.  Here the buffer
    index is the section offset, so `+offset` in a chain is `sec_va + offset`.
    """
    off = 0
    while off < size:
        va = va0 + off
        n = min(PAGE - (va & 0xFFF), size - off)
        pa = w.page_pa(va)
        if pa is None:
            st.zero += n
        else:
            try:
                buf[off:off + n] = dl.retry_phys(g, pa, n)
                st.read += n
            except OSError:
                st.fail += n
        off += n


def fp_page(p, pid=0):
    """True when a 4 KiB page carries an EPROCESS based at page+0x80.

    chainprobe's physical fingerprint: a live EPROCESS always has the
    dispatcher type at base+0 (+0x80 in the page), a pid at base+0x1d0, a
    kernel VA on one of the two link lanes and a printable ImageFileName.
    It does not need the name scan, a DTB, or the object to be first in a
    list -- a recycled-pid corpse stays in the name scan and can be the only
    hit while its DTB page is already free (p72: 1450 on 0x57e88c000).
    """
    if p[0x80] != 3:
        return False
    if pid:
        if struct.unpack_from("<I", p, 0x250)[0] != pid:
            return False
    else:
        q = struct.unpack_from("<I", p, 0x250)[0]
        if not (4 < q <= 0x100000):
            return False
    if not any(struct.unpack_from("<Q", p, o)[0] >> 48 == 0xFFFF
               for o in (0x1D8 + 0x80, 0x258 + 0x80)):
        return False
    nm = p[0x3B8:0x3B8 + 15].rstrip(b"\x00")
    return len(nm) > 2 and all(0x20 <= c < 0x7F for c in nm)


def fp_scan(g, ranges, pid, cap=400):
    """Page-level fingerprint sweep; a faulted chunk is retried at 4 KiB.

    Raw g.read_phys here, not dl.retry_phys: the retry's 0.05 s sleeps cost
    ~1.6 s on a fully dead 64 KiB chunk, and a third of this map is dead.
    """
    hits = []
    faults = 0
    scanned = 0
    for rlo, rhi in ranges:
        pa = rlo
        while pa < rhi and len(hits) < cap:
            n = min(dl.SCAN_CHUNK, rhi - pa)
            try:
                blk = g.read_phys(pa, n)
            except OSError:
                for sub in range(0, n, PAGE):
                    try:
                        b1 = g.read_phys(pa + sub, PAGE)
                    except OSError:
                        faults += 1
                        continue
                    if fp_page(b1, pid):
                        hits.append(pa + sub)
                        prog("FP %#x (%d)" % (pa + sub, len(hits)))
                pa += n
                scanned += n
                continue
            for off in range(0, n, PAGE):
                if fp_page(blk[off:off + PAGE], pid):
                    hits.append(pa + off)
                    prog("FP %#x (%d)" % (pa + off, len(hits)))
                    if len(hits) >= cap:
                        break
            pa += n
            scanned += n
            if scanned >= dl.CKPT_BYTES:
                scanned = 0
                prog("FPCKPT pa=%#x hits=%d fault=%d t=%.0fs"
                     % (pa, len(hits), faults, time.perf_counter() - dl._T0))
    prog("FPSCANEND hits=%d fault=%d" % (len(hits), faults))
    return hits, faults


def dtb_ok(g, dtb):
    try:
        dl.retry_phys(g, dtb & dl.MASK, PAGE)
        return True
    except OSError:
        return False


def pid_scan(g, ranges, pid, cap=4000, hopmax=None, stride=None):
    """Physical PAs where the 8-byte pid occurs.  C-speed `find`, no shape.

    The name route needs ImageFileName to still read "r5apex_dx12.exe"; a
    stripped name (anti-cheat driver) or a faulted page loses the object
    entirely.  UniqueProcessId cannot be stripped, and its high dword is 0 on
    x64, so the 8-byte pattern is rare enough to shape-check every hit.

    Faults are hopped, not fatal (p104 `PINNED_FAULT`): a page that fails all
    three tries is logged and skipped, a page already in BADPA is skipped without
    being tried at all, and `hopmax` (dl.HOP_MAX) caps how many *consecutive*
    lost pages mean "device gone" instead of "hole" - on trip the scan stops with
    SCANSTOP so the caller can tell the two apart by the same read-back rule that
    settled p104.

    `stride` (dl.HOP_STRIDE, pages) is the width of that hop: p106w proved the
    fault is a contiguous >=64 MiB pocket, so probing every page inside it is 16k
    faults for one edge.  The stride applies only while pages are being lost and
    collapses to 1 the moment one reads, so the pocket's far edge is exact and
    everything behind it is swept normally.  The budget counts hops, not bytes,
    so a strided run must raise `hopmax` in step.
    """
    pat = struct.pack("<Q", pid)        # full UniqueProcessId, high dword 0
    hits = []
    faults = 0
    skipped = 0
    lost = 0                            # consecutive dead pages = hop budget
    scanned = 0
    budget = dl.HOP_MAX if hopmax is None else hopmax
    step = PAGE * (dl.HOP_STRIDE if stride is None else stride)
    dl.HOP_LAST = 0
    dl.FIRST_GOOD = 0
    for rlo, rhi in ranges:
        pa = rlo
        while pa < rhi and len(hits) < cap:
            n = min(dl.SCAN_CHUNK, rhi - pa)
            try:
                blk = g.read_phys(pa, n)
                if not dl.FIRST_GOOD:
                    # the first RAM read after the last fault: a clean run reports
                    # where it started, a strided walk reports where it got out
                    dl.FIRST_GOOD = pa
            except OSError:
                sub = 0
                while sub < n:
                    if dl.in_bad(pa + sub):
                        skipped += 1
                        lost = 0        # a pin is an expected hole, not a dead device
                        dl.FIRST_GOOD = 0
                        sub += step
                        continue
                    b1 = None
                    for _try in range(3):
                        try:
                            b1 = g.read_phys(pa + sub, PAGE)
                            break
                        except OSError:
                            continue
                    if b1 is None:
                        faults += 1
                        lost += 1
                        dl.HOP_LAST = pa + sub
                        dl.FIRST_GOOD = 0
                        prog("HOP page=%#x lost=%d/%d%s"
                             % (pa + sub, lost, budget,
                                "" if step == PAGE else " stride=%d" % (step // PAGE)))
                        if lost >= budget:
                            dl.SCAN_STOPPED = True
                            prog("SCANSTOP pa=%#x hopmax=%d hits=%d"
                                 % (pa + sub, budget, len(hits)))
                            prog("PIDSCANEND hits=%d fault=%d skip=%d first=%#x"
                                 % (len(hits), faults, skipped, dl.FIRST_GOOD))
                            return hits, faults
                        sub += step
                        continue
                    lost = 0
                    if not dl.FIRST_GOOD:
                        dl.FIRST_GOOD = pa + sub
                    i = b1.find(pat)
                    while i >= 0:
                        hits.append(pa + sub + i)
                        i = b1.find(pat, i + 1)
                    if step > PAGE:
                        # the pocket is behind us: pay for every page from here so
                        # the edge is exact and the good RAM is actually swept
                        step = PAGE
                    sub += step
                pa += n
                scanned += n
                continue
            i = blk.find(pat)
            while i >= 0 and len(hits) < cap:
                hits.append(pa + i)
                i = blk.find(pat, i + 1)
            pa += n
            scanned += n
            if scanned >= dl.CKPT_BYTES:
                scanned = 0
                prog("PICKPT pa=%#x hits=%d fault=%d skip=%d t=%.0fs"
                     % (pa, len(hits), faults, skipped, time.perf_counter() - dl._T0))
    prog("PIDSCANEND hits=%d fault=%d skip=%d first=%#x"
         % (len(hits), faults, skipped, dl.FIRST_GOOD))
    return hits, faults


def front_pid(g, pid):
    """Find the live EPROCESS by pid, validate by shape + readable DTB."""
    # usable_ranges treats None as "no window"; a passed 0 becomes hi=0 and
    # silently drops every range, so hand it None.
    ranges, note = dl.usable_ranges(g.ram_top,
                                    OPT["lo"] or None, OPT["hi"] or None)
    log("PID RAMMAP %s ranges=%d window=%s..%s"
        % (note, len(ranges),
           "-" if not OPT["lo"] else "%#x" % OPT["lo"],
           "-" if not OPT["hi"] else "%#x" % OPT["hi"]))
    hits, faults = pid_scan(g, ranges, pid, cap=200000)
    log("PID scan: %d occurrences fault=%d %.1f s"
        % (len(hits), faults, time.perf_counter() - dl._T0))
    cache = {}
    found = []
    for pa in hits:
        page = pa & ~0xFFF
        b = (pa & 0xFFF) - 0x1D0            # base relative to the pid field
        if b < 0 or b + 0x350 > PAGE:
            continue
        if page not in cache:
            try:
                cache[page] = g.read_phys(page, PAGE)
            except OSError:
                cache[page] = None
            if len(cache) > 4096:
                cache.clear()
        p = cache[page]
        if p is None or p[b] != 3:
            continue
        dtb = struct.unpack_from("<Q", p, b + 0x28)[0]
        nm = p[b + 0x338:b + 0x338 + 15].rstrip(b"\x00")
        log("  pid@%#x base=%#x type=%d name=%r dtb=%#x"
            % (pa, page + b, p[b], nm, dtb))
        if not dtb or not dl.valid_cr3(g, dtb):
            continue
        ok = dtb_ok(g, dtb)
        log("  pid@%#x base=%#x type=%d name=%r dtb=%#x readable=%s"
            % (pa, page + b, p[b], nm, dtb, ok))
        if ok:
            found.append((page + b, dtb))
    if not found:
        return None
    for base, dtb in found:
        try:
            r = dl.find_mz(g, dtb)
        except OSError as e:
            log("  walk dtb=%#x fault %s" % (dtb, e))
            continue
        if r:
            log("  walk dtb=%#x -> image va=%#x secs=%d"
                % (dtb, r[0], len(r[1]["secs"])))
            return r[0], r[1], dtb
        log("  walk dtb=%#x -> no PE (%s)" % (dtb, dl.probe_dtb(g, dtb)))
    return None


def front_fingerprint(g, pid):
    """Find the live EPROCESS by shape, require a readable DTB page."""
    ranges, note = dl.usable_ranges(g.ram_top,
                                    OPT["lo"] or None, OPT["hi"] or None)
    log("FP RAMMAP %s ranges=%d window=%s..%s"
        % (note, len(ranges),
           "-" if not OPT["lo"] else "%#x" % OPT["lo"],
           "-" if not OPT["hi"] else "%#x" % OPT["hi"]))
    hits, faults = fp_scan(g, ranges, pid)
    log("FP scan: %d pages pid=%d fault=%d %.1f s"
        % (len(hits), pid, faults, time.perf_counter() - dl._T0))
    found = []
    for pa in hits:
        try:
            p = dl.retry_phys(g, pa, PAGE)
        except OSError:
            continue
        b = 0x80
        dtb = struct.unpack_from("<Q", p, b + 0x28)[0]
        if not dtb or not dl.valid_cr3(g, dtb):
            log("  fp %#x dtb=%#x invalid" % (pa, dtb))
            continue
        ok = dtb_ok(g, dtb)
        log("  fp %#x type=%d dtb=%#x readable=%s links=%#x/%#x"
            % (pa, p[b], dtb, ok,
               struct.unpack_from("<Q", p, 0x258)[0],
               struct.unpack_from("<Q", p, 0x260)[0]))
        if ok:
            found.append((pa, dtb))
    if not found:
        return None
    for pa, dtb in found:
        try:
            r = dl.find_mz(g, dtb)
        except OSError as e:
            log("  walk dtb=%#x fault %s" % (dtb, e))
            continue
        if r:
            log("  walk dtb=%#x -> image va=%#x secs=%d"
                % (dtb, r[0], len(r[1]["secs"])))
            return r[0], r[1], dtb
        log("  walk dtb=%#x -> no PE (%s)" % (dtb, dl.probe_dtb(g, dtb)))
    return None


def base_reuse(g):
    """`--dtb` + `--base` shortcut: one PE validate instead of scan + find_mz."""
    if not (OPT["dtb"] and OPT["base"]):
        return None
    if not dl.valid_cr3(g, OPT["dtb"]):
        return None
    try:
        w = dl.Walk(g, OPT["dtb"])
        pa = w.page_pa(OPT["base"])
        if pa is None:
            return None
        meta = dl.validate_pe(dl.retry_phys(g, pa, PAGE))
    except OSError as e:
        log("base reuse fault %s" % e)
        return None
    if not meta:
        return None
    log("REUSE base=%#x dtb=%#x size=%#x (scan + find_mz skipped)"
        % (OPT["base"], OPT["dtb"], meta["size"]))
    return OPT["base"], meta, OPT["dtb"]


def stage_map(pid, target):
    log("p72 map  %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
    log("pure-read: device open only, no load / DSE / service touch")
    log("pid=%d alive=%s target=%#x" % (pid, dl.pid_alive(pid), target))
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        log("FATAL: %s" % e)
        return dl._finish(1, "FATAL no transport")
    try:
        log("target ram=%s (installed=%d MiB)"
            % ("yes" if g.is_ram(target) else "NO", g.ram_top >> 20))
        if not g.is_ram(target):
            return dl._finish(2, "TARGET_NOT_RAM %#x" % target)
        front = base_reuse(g)
        if not front and OPT["front"] in ("both", "name"):
            front = front_half(g, pid)
        if not front and OPT["front"] in ("both", "fp"):
            # The name route can end on a recycled-pid corpse whose DTB page is
            # already free; the shape route finds a live object instead.
            log("name route empty -> fingerprint front")
            prog("FRONT fingerprint fallback")
            front = front_fingerprint(g, pid)
        if not front and OPT["front"] in ("both", "pid"):
            # Last resort: the pid cannot be stripped, the name can.
            log("fingerprint empty -> pid front")
            prog("FRONT pid fallback")
            front = front_pid(g, pid)
        if not front:
            return dl._finish(3, "NO_BASE pid=%d" % pid)
        base, meta, dtb = front
        log("chosen base=%#x size=%#x hdr=%#x dtb=%#x"
            % (base, meta["size"], meta["hdr"], dtb))
        log("sections: " + " ".join("%s@%#x+%#x" % s for s in meta["secs"]))
        if not (CANON_LO <= base < CANON_HI):
            return dl._finish(4, "BAD_BASE %#x" % base)
        sec = section(meta, OPT["sec"])
        if sec is None:
            return dl._finish(4, "NO_SECTION %s (have %s)"
                              % (OPT["sec"],
                                 ",".join(s[0] for s in meta["secs"])))
        sec_va, sec_size = sec
        size = min(sec_size, OPT["maxsec"])
        log("dump section %s va=%#x vsize=%#x take=%#x%s"
            % (OPT["sec"], sec_va, sec_size, size,
               " TRUNCATED" if size < sec_size else ""))
        prog("DUMPSEC %s va=%#x vsize=%#x take=%#x"
             % (OPT["sec"], sec_va, sec_size, size))
        buf = bytearray(size)
        st = dl.Stats()
        w = dl.Walk(g, dtb)
        t0 = time.perf_counter()
        dump_section(g, w, buf, base + sec_va, size, st)
        log("dump: read=%d zero=%d fail=%d %.1f s"
            % (st.read, st.zero, st.fail, time.perf_counter() - t0))
        if st.read < 0x100000:
            return dl._finish(5, "DUMP_THIN read=%d" % st.read)
        os.makedirs(os.path.dirname(DATA), exist_ok=True)
        with open(DATA, "wb") as f:
            f.write(buf)
        sha = hashlib.sha256(buf).hexdigest()
        write_map([("PID", pid), ("TARGET", "%#x" % target),
                   ("BASE", "%#x" % base), ("DTB", "%#x" % dtb),
                   ("SEC", OPT["sec"]), ("SEC_VA", "%#x" % sec_va),
                   ("SEC_SIZE", "%#x" % sec_size), ("TAKE", "%#x" % size),
                   ("FILE", DATA), ("SHA", sha),
                   ("PID_START", time.strftime("%H:%M:%S"))])
        log("DATA %s size=%#x sha=%s" % (DATA, size, sha))
        if not dl.pid_alive(pid):
            return dl._finish(6, "PID_DIED")
        return dl._finish(0, "MAP_OK base=%#x sec=%s take=%#x"
                          % (base, OPT["sec"], size))
    finally:
        try:
            g.close()
        except OSError:
            pass


# ---------------------------------------------------------------- stage chain
class Pages(object):
    """PA -> page bytes with a bounded cache.  BFS revisits pages constantly
    (one page holds up to 512 pointers), so the cache is what keeps this in
    one ioctl per distinct page instead of one per edge."""

    def __init__(self, g):
        self.g = g
        self.cache = {}

    def get(self, page):
        if page in self.cache:
            return self.cache[page]
        if len(self.cache) >= PAGECACHE:
            self.cache.clear()
        try:
            b = dl.retry_phys(self.g, page, PAGE)
        except OSError:
            b = None
        self.cache[page] = b
        return b


def resolve_chain(g, w, base, sec_va, chain):
    """Re-walk a chain from the section dump against live memory.

    chain = (seed_off, k1, k2, ..).  seed_off is the offset in the dump, each
    kN is added to the value just dereferenced before the next deref -- the
    same arithmetic the consumer will run.  -> (landing_va, ""|why)
    """
    p = base + sec_va + chain[0]
    cur = None
    for i, k in enumerate((0,) + chain[1:]):
        if cur is not None:
            cur += k
            p = cur
        page = w.page_pa(p)
        if page is None:
            return None, "hop absent @%#x" % p
        try:
            q = struct.unpack("<Q", dl.retry_phys(g, page + (p & 0xFFF), 8))[0]
        except OSError as e:
            return None, "hop read %s @%#x" % (e, p)
        if not canon(q):
            return None, "hop not canon %#x @%#x" % (q, p)
        cur = q
    return cur, ""


def floats_at(buf, off, n=6):
    out = []
    for i in range(n):
        o = off + 4 * i
        if o + 4 > len(buf):
            break
        u = struct.unpack_from("<I", buf, o)[0]
        f = struct.unpack_from("<f", buf, o)[0]
        ok = f == f and 1e-6 < abs(f) < 1e6
        out.append("%s%08x%s" % ("+" if i else "", u, "~%.3f" % f if ok else ""))
    return " ".join(out)


def stage_chain():
    log("p72 chain  %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
    log("pure-read: device open only")
    if not os.path.exists(MAP):
        return dl._finish(2, "NO_MAP %s" % MAP)
    m = read_map()
    try:
        pid = int(m["PID"])
        target = int(m["TARGET"], 16)
        base = int(m["BASE"], 16)
        dtb = int(m["DTB"], 16)
        sec_va = int(m["SEC_VA"], 16)
        take = int(m["TAKE"], 16)
    except (KeyError, ValueError) as e:
        return dl._finish(2, "BAD_MAP %s" % e)
    log("map: pid=%d target=%#x base=%#x dtb=%#x sec=%s va=%#x take=%#x"
        % (pid, target, base, dtb, m.get("SEC"), sec_va, take))
    log("map written %s, pid_start=%s" % (m.get("PID_START"), m.get("SHA", "")[:16]))
    if not dl.pid_alive(pid):
        return dl._finish(2, "STALE_PID %d dead" % pid)
    want = OPT["want"] & 0xFFF
    target_page = target & ~0xFFF
    try:
        data = open(m["FILE"], "rb").read()
    except OSError as e:
        return dl._finish(2, "NO_DATA %s" % e)
    if len(data) != take:
        return dl._finish(2, "DATA_SIZE %d != %d" % (len(data), take))
    if hashlib.sha256(data).hexdigest() != m.get("SHA"):
        return dl._finish(2, "DATA_SHA mismatch")
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        return dl._finish(1, "FATAL %s" % e)
    try:
        w = dl.Walk(g, dtb)
        if w.page_pa(base) is None:
            return dl._finish(3, "STALE_MAP base page absent under dtb=%#x" % dtb)
        try:
            tbuf = dl.retry_phys(g, target_page, PAGE)
        except OSError as e:
            return dl._finish(3, "TARGET_FAULT %s" % e)
        log("target page %#x read ok, head: %s" % (target_page, floats_at(tbuf, 0)))

        seeds = []
        for off in range(0, len(data) - 8, 8):
            q = struct.unpack_from("<Q", data, off)[0]
            if canon(q):
                seeds.append((off, q))
        log("SEEDS canon=%d of %d qwords (%.1f%%)"
            % (len(seeds), len(data) // 8, 100.0 * len(seeds) / max(1, len(data) // 8)))
        prog("SEEDS %d take=%#x" % (len(seeds), take))
        if not seeds:
            return dl._finish(4, "NO_SEEDS sec=%s" % m.get("SEC"))

        frontier = [(q, (off,)) for off, q in seeds]
        depth = 1
        nodes = 0
        stopped = "covered"
        hits = []
        seen = set()
        pages = Pages(g)
        while frontier:
            if depth > OPT["depth"]:
                stopped = "depth"
                break
            if nodes >= OPT["nodes"]:
                stopped = "nodetrip"
                break
            nxt = []
            lh = 0
            for q, chain in frontier:
                if nodes >= OPT["nodes"]:
                    stopped = "nodetrip"
                    break
                nodes += 1
                page = w.page_pa(q)
                if page is None:
                    continue
                if page == target_page:
                    hits.append((depth, chain, q & 0xFFF))
                    lh += 1
                    prog("HIT d=%d landing=%#x" % (depth, q & 0xFFF))
                    if len(hits) >= HITCAP:
                        stopped = "hitcap"
                        break
                    continue
                if depth == OPT["depth"]:
                    continue
                buf = pages.get(page)
                if buf is None:
                    continue
                ptrs = [o for o in range(0, PAGE - 8, 8)
                        if canon(struct.unpack_from("<Q", buf, o)[0])]
                if not ptrs:
                    continue
                for o in sample(ptrs, OPT["branch"]):
                    child = struct.unpack_from("<Q", buf, o)[0]
                    if child in seen:
                        continue
                    seen.add(child)
                    nxt.append((child, chain + (o - (q & 0xFFF),)))
            log("LEVEL %d frontier=%d nodes=%d hits=%d next=%d"
                % (depth, len(frontier), nodes, lh, len(nxt)))
            if hits and len(hits) >= HITCAP:
                break
            frontier = nxt
            depth += 1
        log("BFS done: nodes=%d hits=%d stopped=%s"
            % (nodes, len(hits), stopped))

        if not hits:
            return dl._finish(5, "CHAIN_NONE nodes=%d stopped=%s" % (nodes, stopped))

        # R3: the BFS table is a claim; only a fresh walk against live memory
        # is evidence.  Every accepted chain is re-resolved byte by byte and
        # its landing must still be the target page.
        hits.sort(key=lambda h: (h[0], abs(h[2] - want)))
        log("top hits: %d (verifying %d)" % (len(hits), min(12, len(hits))))
        good = []
        for depth, chain, landing in hits[:12]:
            va, why = resolve_chain(g, w, base, sec_va, chain)
            ok = va is not None and w.page_pa(va) == target_page
            spec = "seed=+%#x" % chain[0]
            if chain[1:]:
                spec += " hops=" + ",".join("%+#x" % k for k in chain[1:])
            log("RESULT d=%d %s landing=%#x dist=%#x ok=%d %s"
                % (depth, spec, landing, abs(landing - want), 1 if ok else 0,
                   "" if ok else why))
            if ok:
                good.append((depth, chain, landing, va))
        if not good:
            return dl._finish(5, "CHAIN_UNVERIFIED %d candidates" % len(hits))

        live = Pages(g)
        tnow = live.get(target_page)
        for depth, chain, landing, va in good[:5]:
            spec = "seed=+%#x" % chain[0]
            if chain[1:]:
                spec += " hops=" + ",".join("%+#x" % k for k in chain[1:])
            log("CHAIN d=%d %s va=%#x" % (depth, spec, va))
        best = good[0]
        d, chain, landing, va = best
        log("landing +%#x floats: %s"
            % (landing, floats_at(tnow, landing) if tnow else "page fault"))
        if not dl.pid_alive(pid):
            return dl._finish(6, "PID_DIED")
        spec = "r5apex_dx12+%#x" % (sec_va + chain[0])
        for k in chain[1:]:
            spec += " -> %+#x" % k
        return dl._finish(0, "CHAIN hits=%d verified=%d depth=%d %s landing=%#x"
                          " dist=%#x stopped=%s"
                          % (len(hits), len(good), d, spec, landing,
                             abs(landing - want), stopped))
    finally:
        try:
            g.close()
        except OSError:
            pass


# ---------------------------------------------------------------- main
def find_pid():
    return dl.find_pid()


def main():
    pid = None
    for a in sys.argv[1:]:
        if a.startswith("--stage="):
            OPT["stage"] = a[8:]
        elif a.startswith("--pid="):
            OPT["pid"] = int(a[6:])
        elif a.startswith("--target="):
            OPT["target"] = int(a[9:], 0)
        elif a.startswith("--depth="):
            OPT["depth"] = int(a[8:])
        elif a.startswith("--nodes="):
            OPT["nodes"] = int(a[8:])
        elif a.startswith("--branch="):
            OPT["branch"] = int(a[9:])
        elif a.startswith("--maxsec="):
            OPT["maxsec"] = int(a[9:], 0)
        elif a.startswith("--sec="):
            OPT["sec"] = a[6:]
        elif a.startswith("--want="):
            OPT["want"] = int(a[7:], 0)
        elif a.startswith("--dtb="):
            OPT["dtb"] = int(a[6:], 0)
        elif a.startswith("--base="):
            OPT["base"] = int(a[7:], 0)
        elif a == "--inplace":
            OPT["inplace"] = True
        elif a.startswith("--front="):
            OPT["front"] = a[8:]
        elif a.startswith("--lo="):
            OPT["lo"] = int(a[5:], 0)
        elif a.startswith("--hi="):
            OPT["hi"] = int(a[5:], 0)
    if OPT["stage"] == "chain":
        if not OPT["inplace"] and dl.elevation() != 1 and "--elevated" not in sys.argv:
            return relaunch()
        return stage_chain()
    pid = OPT["pid"] or find_pid()
    if not pid:
        print("no r5apex_dx12 process found")
        return 2
    if not OPT["target"]:
        print("usage: --stage=map --pid=N --target=PA")
        return 2
    if OPT["inplace"] or dl.elevation() == 1 or "--elevated" in sys.argv:
        if dl.elevation() != 1:
            log("WARNING: inplace but token is NOT elevated")
        return stage_map(pid, OPT["target"])
    return relaunch(pid)


def relaunch(pid=0):
    args = [sys.executable, os.path.abspath(sys.argv[0]), "--elevated",
            "--stage=%s" % OPT["stage"]]
    if OPT["stage"] == "map":
        args.append("--pid=%d" % pid)
        args.append("--target=%#x" % OPT["target"])
        args.append("--sec=%s" % OPT["sec"])
        args.append("--maxsec=%#x" % OPT["maxsec"])
        if OPT["dtb"]:
            args.append("--dtb=%#x" % OPT["dtb"])
        if OPT["base"]:
            args.append("--base=%#x" % OPT["base"])
        if OPT["front"] != "both":
            args.append("--front=%s" % OPT["front"])
        if OPT["lo"]:
            args.append("--lo=%#x" % OPT["lo"])
        if OPT["hi"]:
            args.append("--hi=%#x" % OPT["hi"])
    else:
        args.append("--depth=%d" % OPT["depth"])
        args.append("--nodes=%d" % OPT["nodes"])
        args.append("--branch=%d" % OPT["branch"])
        args.append("--want=%#x" % OPT["want"])
    params = subprocess.list2cmdline(args)
    try:
        os.remove(OUT)
    except OSError:
        pass
    print("parent: elevating")
    print("parent: params=%s" % params)
    msg = dl.run_elevated(params)
    print(msg)
    if not os.path.exists(OUT):
        log("parent: elevation returned %r" % msg)
        return dl._finish(3, "ELEV_FAIL %s" % msg)
    print(open(OUT, encoding="utf-8").read())
    return 0


if __name__ == "__main__":
    sys.exit(main())

