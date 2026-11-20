# -*- coding: utf-8 -*-
"""probe1450.py - frame 0x3856ea000 flaps readable/unreadable.  Quantify it. READ-ONLY.

Timeline contradiction to resolve:
  21:08 Walk(0x3856ea000) ctor OK   (round-1 'try dtb -> no PE' implies descent ran)
  22:15 Walk(0x3856ea000) ctor OK   (round-2 same line)
  22:25 Walk(0x3856ea000) ctor DEAD (instant errno 1450, unretried)
Tests, all read-only, seconds long:
  [A] retry_phys(6) assault x3 on the frame       - does the medicine still work?
  [B] EPROCESS re-derivation at 0x224f62080       - does it still claim this DTB?
  [C] readability census of old-boot DTB frames   - regime gauge
  [D] neighbor geometry 0x3856e9000..0x385708000  - scattered or contiguous?
  [E] conditional: on [B] giving MZ via find_mz   - seed temp\\qk_dtb_25548.txt
Evidence: temp\\probe1450_out.txt
"""
import os
import struct
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
OUT = os.path.join(TMP, "probe1450_out.txt")
LOG = []

FRAME = 0x3856EA000
EPROC_PAGE = 0x224F62000
EPROC_BASE = 0x224F62080
OLD_FRAMES = (0x34C9EE000, 0x3AD092000, 0x3AD091000, 0x3AD090000)
NEIGH_LO = 0x3856E9000
NEIGH_HI = 0x385709000
TARGET_PID = 25548


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


def raw_try(g, pa, n=0x1000):
    t0 = time.perf_counter()
    try:
        b = g.read_phys(pa, n)
        return ("OK", len(b) if b else 0, time.perf_counter() - t0)
    except OSError as e:
        return ("FAULT", str(e), time.perf_counter() - t0)


def main():
    out("=== probe1450 %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
    try:
        g = gio.Gio()
    except OSError as e:
        out("gio open failed: %s" % e)
        out("VERDICT: SKIP - no transport")
        flush()
        return
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    orig_is_ram = g.is_ram
    if qv is not None and hasattr(qv, "Ram"):
        ram = qv.Ram(ranges)
        g.is_ram = ram.page_ok
        out("is_ram strengthened (%s, %d ranges)" % (note, len(ranges)))

    # [A] retry assault on the PML4 frame itself
    ok_any = 0
    for rnd in range(3):
        t0 = time.perf_counter()
        try:
            b = dl.retry_phys(g, FRAME, 0x1000, tries=6)
            ok_any += 1
            got = "len=%d e0=%#x" % (len(b), struct.unpack_from("<Q", b)[0])
        except OSError as e:
            got = "%s" % e
        out("[A] round%d retry6(%#x) -> %s (%.1fs)"
            % (rnd, FRAME, got, time.perf_counter() - t0))
        time.sleep(0.2)
    out("[A] successes=%d/3" % ok_any)

    # [B] EPROCESS re-derivation
    try:
        pg = g.read_phys(EPROC_PAGE, 0x1000)
        tbyte = pg[EPROC_BASE - EPROC_PAGE]
        dtb_q = struct.unpack_from("<Q", pg, EPROC_BASE + 0x28 - EPROC_PAGE)[0]
        out("[B] EPROC type=%d dtb_field=%#x (claimed:%#x match=%s)"
            % (tbyte, dtb_q, FRAME, dtb_q == FRAME))
    except OSError as e:
        out("[B] EPROC page unreadable: %s" % e)
        dtb_q = None

    # [C] old-boot frame census (single-shot, regime gauge)
    for f in OLD_FRAMES:
        st, why, dt = raw_try(g, f)
        out("[C] %#x -> %s (%.2fs)" % (f, st if st == "OK" else why, dt))

    # [D] neighbor geometry
    ok = dead = 0
    geo = []
    for pa in range(NEIGH_LO, NEIGH_HI, 0x1000):
        st, why, _ = raw_try(g, pa, 0x1000)
        if st == "OK":
            ok += 1
            geo.append(".")
        else:
            dead += 1
            geo.append("X")
    out("[D] neighbors %#x..%#x ok=%d dead=%d map=%s"
        % (NEIGH_LO, NEIGH_HI, ok, dead, "".join(geo)))

    # [E] conditional revival: assault + find_mz + validated seed
    revived = None
    if ok_any:
        try:
            r = dl.find_mz(g, FRAME)
            if r:
                revived = r
                out("[E] find_mz(after assault) -> MZ@%#x meta=%r" % (r[0], r[1]))
            else:
                out("[E] find_mz(after assault) -> None (descent ran, no PE)")
        except OSError as e:
            out("[E] find_mz raised %s" % e)
    if revived:
        cache = os.path.join(TMP, "qk_dtb_%d.txt" % TARGET_PID)
        try:
            with open(cache, "w", encoding="utf-8") as f:
                f.write("pid=%d\ndtb=0x%X\nbase=0x%X\n"
                        % (TARGET_PID, FRAME, revived[0]))
            out("ACTION: cache seeded %s (reverse = delete file)" % cache)
        except OSError as e:
            out("ACTION: seed failed %s" % e)

    # verdict
    if revived:
        out("RESULT: dtb=0x3856ea000 REVIVED AND PRODUCTIVE")
        out("VERDICT: PASS - flapping root page; retry-assault recovers it; cache seeded")
    elif ok_any:
        out("RESULT: dtb readable-after-retry but no PE beneath it")
        out("VERDICT: FAIL-NODESCENT - frame alive, page table contents say no image")
    else:
        out("RESULT: dtb frame hard-dead to retry6 as well; check [B]/[C]/[D]")
        out("VERDICT: FAIL-FRAMEDEAD - if [B] still claims it, root page is hostile")
    try:
        g.is_ram = orig_is_ram
    except Exception:  # noqa: BLE001
        pass
    flush()


if __name__ == "__main__":
    main()