# -*- coding: utf-8 -*-
"""qk_dtb_probe.py - why does dtb 0x3856ea000 walk to no PE?  READ-ONLY probe.

Round-1 (21:07) and round-2 (22:14) name sweeps INDEPENDENTLY derived
  EPROCESS @ 0x224f62080, DTB 0x3856ea000, ImageFileName off 0x338.
Only find_mz disagrees ("no PE").  This probe separates:
  1. dl.probe_dtb census  : which MMU level is absent (uses bare read_phys,
                            so counts read LOW - interpret directionally).
  2. dl.find_mz direct    : the exact callable the runners used.
  3. Manual VA walk       : PML4 user-image country + historical bases.
  4. Cache-seed (ACTION)  : only on validated MZ, write temp\\qk_dtb_25548.txt
                            so the next producer's get_map() hits instantly.
                            Reversible: delete the file.
Evidence: temp\\probe_dtb_out.txt
"""
import glob
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))

import gio            # noqa: E402
import dumplive as dl  # noqa: E402
try:
    import qk_va as qv  # noqa: E402
except Exception:       # noqa: BLE001
    qv = None

TMP = os.path.join(ROOT, "temp")
OUT = os.path.join(TMP, "probe_dtb_out.txt")
LOG = []


def out(s):
    line = str(s)
    LOG.append(line)
    print(line)


def flush():
    try:
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("\n".join(LOG) + "\n")
    except OSError as e:
        print("flush fail: %s" % e)


TARGET_PID = 25548
TARGET_DTB = 0x3856EA000


def manual_level(g, dtb, va):
    """Walk one VA down all four levels, reporting each level's raw truth."""
    MASK = dl.MASK
    rep = []
    try:
        w = dl.Walk(g, dtb)
    except OSError as e:
        return "walk-ctor: %s" % e
    i4 = (va >> 39) & 0x1FF
    e4 = dl.u64(w.pml4, i4 * 8)
    rep.append("pml4[%d]=%#x" % (i4, e4))
    if not (e4 & 1):
        return " ".join(rep) + " -> not-present"
    pdpt_pa = e4 & MASK
    if not g.is_ram(pdpt_pa):
        return " ".join(rep) + " -> pdpt not-ram"
    try:
        pdpt = dl.retry_phys(g, pdpt_pa, 0x1000)
    except OSError as e:
        return " ".join(rep) + " -> pdpt fault %s" % e
    ii = (va >> 30) & 0x1FF
    e3 = dl.u64(pdpt, ii * 8)
    rep.append("pdpt[%d]=%#x" % (ii, e3))
    if not (e3 & 1):
        return " ".join(rep) + " -> not-present"
    if e3 & 0x80:
        return " ".join(rep) + " -> 1GiB leaf"
    pd_pa = e3 & MASK
    if not g.is_ram(pd_pa):
        return " ".join(rep) + " -> pd not-ram"
    try:
        pd = dl.retry_phys(g, pd_pa, 0x1000)
    except OSError as e:
        return " ".join(rep) + " -> pd fault %s" % e
    jj = (va >> 21) & 0x1FF
    d = dl.u64(pd, jj * 8)
    rep.append("pd[%d]=%#x" % (jj, d))
    if not (d & 1):
        return " ".join(rep) + " -> not-present"
    if d & 0x80:
        try:
            head = dl.retry_phys(g, d & MASK, 2)
        except OSError as e:
            return " ".join(rep) + " -> 2MiB-leaf fault %s" % e
        return " ".join(rep) + " -> 2MiB-leaf head=%r" % head
    pt_pa = d & MASK
    if not g.is_ram(pt_pa):
        return " ".join(rep) + " -> pt not-ram"
    try:
        pt = dl.retry_phys(g, pt_pa, 0x1000)
    except OSError as e:
        return " ".join(rep) + " -> pt fault %s" % e
    kk = (va >> 12) & 0x1FF
    pte = dl.u64(pt, kk * 8)
    rep.append("pte[%d]=%#x" % (kk, pte))
    if not (pte & 1):
        return " ".join(rep) + " -> not-present"
    pa = pte & MASK
    if not g.is_ram(pa):
        return " ".join(rep) + " -> leaf not-ram"
    try:
        head = dl.retry_phys(g, pa, 64)
    except OSError as e:
        return " ".join(rep) + " -> leaf fault %s" % e
def hist_bases():
    """(pid, dtb, base) tuples from surviving temp\\qk_dtb_*.txt caches."""
    got = []
    for p in sorted(glob.glob(os.path.join(TMP, "qk_dtb_*.txt"))):
        k = {}
        try:
            with open(p, "r", encoding="utf-8") as f:
                for ln in f:
                    if "=" in ln:
                        a, b = ln.strip().split("=", 1)
                        k[a] = int(b, 16) if b.lower().startswith("0x") else int(b)
            if k.get("pid") and k.get("base"):
                got.append((k["pid"], k.get("dtb", 0), k["base"]))
        except (OSError, ValueError):
            continue
    return got


def main():
    out("=== qk_dtb_probe %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
    out("target dtb=%#x pid=%d" % (TARGET_DTB, TARGET_PID))
    try:
        g = gio.Gio()
    except OSError as e:
        out("gio open failed: %s" % e)
        out("RESULT: no-transport")
        out("VERDICT: SKIP - gdrv3 not reachable from probe")
        flush()
        return
    out("ram_top=%#x" % g.ram_top)
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    orig_is_ram = g.is_ram
    if qv is not None and hasattr(qv, "Ram"):
        ram = qv.Ram(ranges)
        g.is_ram = ram.page_ok
        out("is_ram strengthened via qk_va.Ram (%s, %d ranges)" % (note, len(ranges)))
    else:
        out("WARNING: qk_va.Ram unavailable - factory is_ram in effect (%s)" % note)

    # --- 1. level census
    t0 = time.perf_counter()
    try:
        c = dl.probe_dtb(g, TARGET_DTB)
    except OSError as e:
        c = "probe_dtb fault %s" % e
    out("[1] probe_dtb -> %s (%.1fs)" % (c, time.perf_counter() - t0))

    # --- 2. the exact callable the runners used
    r = None
    t0 = time.perf_counter()
    try:
        r = dl.find_mz(g, TARGET_DTB)
    except OSError as e:
        out("[2] find_mz raised %s: %s" % (type(e).__name__, e))
    out("[2] find_mz -> %s (%.1fs)"
        % (("MZ@%#x meta=%r" % (r[0], r[1])) if r else "None",
           time.perf_counter() - t0))

    # --- 3. manual walks: historical bases + user-image anchor families
    fam = {}
    for pid, dtb, base in hist_bases():
        out("[hist] pid=%d dtb=%#x base=%#x" % (pid, dtb, base))
        fam.setdefault(base & ~0xFFFFFFFFFFF, []).append((base, pid))
    for anchor in (0x7FF600000000, 0x7FF680000000, 0x7FF700000000):
        fam.setdefault(anchor, [])
    mzs = []
    for anchor, lst in sorted(fam.items()):
        if anchor < 0x10000:
            continue
        out("[3] va=%#012x %s" % (anchor, manual_level(g, TARGET_DTB, anchor)))
        for base, pid in lst[:2]:
            for inc in (0, 0x1000, 0x10000, 0x100000):
                det = manual_level(g, TARGET_DTB, base + inc)
                out("[3]   pid%d base+%#x %s" % (pid, inc, det))
                if "head=b'MZ'" in det:
                    mzs.append((base + inc, pid, inc))
    out("[3] MZ-bearing VAs: %r" % (mzs[:8],) if mzs else "[3] none of the probed VAs carried MZ")

    # --- verdict + conditional cache seed
    seeded = False
    if r and isinstance(r, tuple):
        base_found = r[0]
        out("RESULT: dtb-alive find_mz VA=%#x meta=%r" % (base_found, r[1]))
        out("VERDICT: PASS - 0x3856ea000 maps a PE; tonight's runs failed elsewhere")
        cache = os.path.join(TMP, "qk_dtb_%d.txt" % TARGET_PID)
        try:
            with open(cache, "w", encoding="utf-8") as f:
                f.write("pid=%d\ndtb=0x%X\nbase=0x%X\n"
                        % (TARGET_PID, TARGET_DTB, base_found))
            seeded = True
            out("ACTION: cache seeded %s (reverse = delete file)" % cache)
        except OSError as e:
            out("ACTION: cache seed failed %s" % e)
    elif mzs:
        out("RESULT: dtb-alive manual-walk MZ=%#x (find_mz blind)" % mzs[0][0])
        out("VERDICT: PASS-MANUAL - walker bug confirmed; seed meta next step")
    else:
        out("RESULT: dtb-dead-or-blind - census line names the missing level")
        out("VERDICT: FAIL-NODTB - no callable, no manual walk saw a PE")
    out("seeded=%s" % seeded)
    try:
        g.is_ram = orig_is_ram
    except Exception:  # noqa: BLE001
        pass
    flush()


if __name__ == "__main__":
    main()