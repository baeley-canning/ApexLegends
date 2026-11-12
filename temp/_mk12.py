"""mk12: flakiness matrix + map-path cross-test for the e1450 family.

mk11 found the LIVE EPROCESS of pid 26496 (0x13cf13010, VALID) but its fresh
DTB frame 0x5732e3000 stormed 12/12 e1450 - the THIRD game DTB on the "dead"
set (lottery falsified).  mk11 also saw FLAKY pages: 0x5d28f1000 read fine in
the sweep (a name hit lived on it) then failed e1450 on re-read seconds later.
So "dead" may be a time-varying, per-page property of the READ ioctl, not a
property of the frame.

Two questions, one probe (read-only, gdrv3 only):
  A. cadence matrix: 60 spaced (50 ms) read_phys per target - hard-dead (0/60)
     vs flaky (mixed) vs solid (60/60); first-qword of each success tracks
     content stability.
  B. map-path cross-test: for every hard-dead target, map_phys() (IOCTL_MAP_EX
     -> user VA) and read the page through the VA.  If the map path reads a
     frame the read ioctl refuses, the M1 transport gate reopens via Walk on
     map_phys.  Control first: ctrl page via BOTH paths must match byte for
     byte, or the map path is untrusted and B is skipped.

R4: every map_phys is unmapped in the same script.  GIO_DST_LAST=1 (p91 close
order).  All PAs guarded by the usable-map interval set (R10).  _mk12_out.txt.
"""
import ctypes
import os
import sys
import time

os.environ["GIO_DST_LAST"] = "1"            # p91: handle first, dst second

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))
import gio                     # noqa: E402
import dumplive as dl          # noqa: E402

OUT = os.path.join(HERE, "_mk12_out.txt")
PAGE = 0x1000
READS = 60
GAP = 0.05
TARGETS = [
    ("dtb_new  ", 0x5732E3000),   # pid 26496 PML4 frame (mk11 VALID obj)
    ("dtb_6004 ", 0x6EF568000),   # 17:20 instance DTB, dead since 18:0x
    ("dtb_20612", 0x436AD8000),   # earlier instance DTB
    ("wasok    ", 0x6EF980000),   # read ok in _mk, dead in _mk3/_mk4/_mk5
    ("flaky    ", 0x5D28F1000),   # sweep-ok then dead in mk11 validation
    ("obj_new  ", 0x13CF13000),   # live EPROCESS page (expect solid)
    ("ctrl     ", 0x436A00000),   # never-failed witness (post-state)
]


def say(s):
    line = str(s)
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== mk12 flakiness + map-path probe %s ===" % time.strftime("%H:%M:%S"))
    g = gio.Gio(chunk=PAGE)
    ranges, note = dl.usable_ranges(g.ram_top, None, None, [])
    say("ram_top=%#x ranges=%d (%s)" % (g.ram_top, len(ranges), note))

    def in_map(pa):
        p = pa & ~0xFFF
        return any(a <= p and p + PAGE <= b for a, b in ranges)

    # ---- control: read vs map on the witness page --------------------------
    map_ok = False
    try:
        ref = g.read_phys(TARGETS[-1][1], PAGE)
        va = g.map_phys(TARGETS[-1][1], PAGE)
        via = ctypes.string_at(va, PAGE)
        g.unmap(va, PAGE)
        same = sum(a == b for a, b in zip(ref, via))
        say("ctrl read-vs-map: %d/%d bytes equal" % (same, PAGE))
        map_ok = same == PAGE
    except OSError as e:
        say("ctrl map-path control FAILED: %r - map path untrusted" % e)
    say("map path trusted=%s" % map_ok)

    # ---- phase A: cadence matrix -------------------------------------------
    results = {}
    for tag, pa in TARGETS:
        if not in_map(pa):
            say("%s %#012x outside map (R10 skip)" % (tag, pa))
            results[tag.strip()] = None
            continue
        pat = []
        errs = {}
        qw = {}
        t0 = time.perf_counter()
        for i in range(READS):
            try:
                buf = g.read_phys(pa, PAGE)
                pat.append("R")
                import struct
                q = struct.unpack_from("<Q", buf)[0]
                qw[q] = qw.get(q, 0) + 1
            except OSError as e:
                pat.append(".")
                errs[e.errno] = errs.get(e.errno, 0) + 1
            if i != READS - 1:
                time.sleep(GAP)
        okn = pat.count("R")
        say("%s %#012x %2d/%d R errs=%s qwords=%d %s (%.1fs)"
            % (tag, pa, okn, READS, errs or "-", len(qw), "".join(pat),
               time.perf_counter() - t0))
        results[tag.strip()] = (pa, okn, qw)
        # mid-probe health witness
        try:
            g.read_phys(TARGETS[-1][1], PAGE)
            say("  health: ctrl READ")
        except OSError as e:
            say("  health: ctrl FAIL e%s" % e.errno)
    # ---- phase B: map-path cross-test on hard-dead targets ------------------
    say("--- phase B: map_phys on hard-dead targets ---")
    dtb_read = None
    for tag, pa in TARGETS:
        key = tag.strip()
        res = results.get(key)
        if not res or res[1] != 0:
            continue                       # only hard-dead pages
        if not map_ok:
            say("%s %#012x map test skipped (path untrusted)" % (tag, pa))
            continue
        try:
            va = g.map_phys(pa, PAGE)
        except OSError as e:
            say("%s %#012x map_phys FAILED: e%s" % (tag, pa, e.errno))
            continue
        import struct
        buf = ctypes.string_at(va, PAGE)
        g.unmap(va, PAGE)
        ent = struct.unpack("<512Q", buf)
        present = sum(1 for x in ent if x & 1)
        selfok = any((x & ~0xFFF) == pa for x in ent)
        nz = sum(1 for b in buf if b)
        say("%s %#012x MAP-READ ok: nonzero=%d present=%d selfref=%s "
            "ent[0]=%#x ent[1]=%#x" % (tag, pa, nz, present, selfok,
                                       ent[0], ent[1]))
        if key == "dtb_new":
            dtb_read = (nz, present, selfok)

    say("RESULT: cadence=%s" % {k: (v[1] if v else None)
                              for k, v in results.items()})
    new = results.get("dtb_new")
    if new and new[1] > 0:
        say("VERDICT: PASS - dtb_new is FLAKY not dead (%d/%d); spaced reads "
            "reopen the M1 gate" % (new[1], READS))
    elif dtb_read and dtb_read[0] > 100:
        say("VERDICT: PASS-WORKAROUND - read ioctl refuses dtb_new but "
            "map_phys reads it (present=%d selfref=%s); port Walk to the map "
            "path" % (dtb_read[1], dtb_read[2]))
    elif new:
        say("VERDICT: FAIL - dtb_new hard-dead on BOTH paths; transport "
            "blocked for this boot")
    else:
        say("VERDICT: PARTIAL - dtb_new skipped (R10)")
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())