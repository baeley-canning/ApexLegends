# -*- coding: utf-8 -*-
r"""h412_dtb_ab.py -- A/B the page-walk machinery against historically-good DTBs.

QUESTION (one variable: VAR=cached_dtb_frames): do page-table walks that reached
an 'MZ' in past sessions still reach one now, on this same host, without Apex?
  SANE          >=1 specimen walks to a real MZ  -> walk machinery + phys reads
                                                  healthy; discovery FLOW is the bug
  CONTENT_BLIND walks complete fault-free but zero MZ anywhere -> leaves read
                 garbage; leans kernel-state damage
  FAULT_WEDGE   faults dominate on formerly-good frames -> transport/state wedged
  NO_SPECIMENS  no cache survived to test
  TRANSPORT_DOWN gio would not open (gdrv3/elevation problem, separate issue)

Read-only: phys reads only, every PA gated by qk_va.Ram page_ok (R10), hops
bounded (<=4 levels), full dl.find_mz deliberately NOT called (p331: unbounded
descent only ever behind a bounded pass; not needed to score the verdict).
No state changed anywhere; outputs land beside this file.
"""
import glob
import os
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio                       # noqa: E402
import dumplive as dl            # noqa: E402
import qk_va as VA               # noqa: E402

OUT = os.path.join(HERE, "h412_dtb_ab.txt")
HARDCODED = [(11192, 0x3AD092000, 0x7FF7049D0000)]   # from temp/probe_dtb_out hist
_f = open(OUT, "w", encoding="utf-8")
_f.close()


def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(str(s) + "\n")


def parse_specimens():
    """(pid, dtb, base, src) from temp\\qk_dtb_*.txt; dedupe; hardcoded last."""
    specs, seen = [], set()
    for fp in sorted(glob.glob(os.path.join(HERE, "qk_dtb_*.txt"))):
        try:
            txt = open(fp, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        mp = re.search(r"^pid=(\d+)", txt, re.M)
        md = re.search(r"^dtb=0x([0-9A-Fa-f]+)", txt, re.M)
        mb = re.search(r"^base=0x([0-9A-Fa-f]+)", txt, re.M)
        if not (md and mb):
            continue
        pid = int(mp.group(1)) if mp else 0
        trip = (pid, int(md.group(1), 16), int(mb.group(1), 16))
        if trip[1] and trip[1] not in seen:
            seen.add(trip[1])
            specs.append(trip + (os.path.basename(fp),))
    for pid, dtb, base in HARDCODED:
        if dtb not in seen:
            specs.append((pid, dtb, base, "hardcoded(probe_dtb hist)"))
    return specs

def walk_bounded(dtb, va, g, stats):
    """4-level walk; returns (leaf_pa | None, note). Counts faults, caps work."""
    t = dtb & 0xFFFFFFFFFF000
    path = []
    for sh in (39, 30, 21):
        pa = t + ((va >> sh) & 0x1FF) * 8
        if not g.is_ram(pa):
            return None, "guard-refused lvl%d pa=%#x" % (sh, pa)
        try:
            b = g.read_phys(pa, 8)
            stats["ok_reads"] += 1
        except OSError as e:
            stats["faults"] += 1
            stats["last_fault"] = str(e)[:80]
            return None, "fault lvl%d: %s" % (sh, str(e)[:60])
        e4 = struct.unpack("<Q", b)[0]
        path.append("%d:%016X" % (sh // 9, e4))
        if not (e4 & 1):
            return None, "absent lvl%d [%s]" % (sh, "/".join(path))
        if (e4 & 0x80) and sh == 21:                       # 2 MiB page
            return (e4 & 0xFFFFFFFFFF000) + (va & 0x1FFFFF), "ok(2M) " + "/".join(path)
        nxt = e4 & 0xFFFFFFFFFF000
        if nxt and not g.is_ram(nxt):
            return None, "guard-refused child pa=%#x" % nxt
        t = nxt
    return t + (va & 0xFFF), "ok " + "/".join(path)


def main():
    t0 = time.time()
    say("h412 start %s py=%s" % (time.strftime("%F %T"), sys.version.split()[0]))
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        say("gio open failed: %s" % e)
        say("VERDICT: TRANSPORT_DOWN")
        return 2
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    ram = VA.Ram(ranges)
    g.is_ram = ram.page_ok                                  # R10 guard, always
    say("ram map: %s (%d ranges) top=%#x" % (note, len(ranges), g.ram_top))

    specs = parse_specimens()
    say("specimens=%d" % len(specs))
    for pid, dtb, base, src in specs:
        say("  SP pid=%d dtb=%#x base=%#x src=%s" % (pid, dtb, base, src))
    if not specs:
        say("VERDICT: NO_SPECIMENS")
        return 3

    stats = {"ok_reads": 0, "faults": 0, "last_fault": ""}
    ok_leaf = 0
    mz_found = None
    for pid, dtb, base, src in specs:
        # hop 0: is the PML4 frame itself still readable?
        try:
            blk = g.read_phys(dtb & 0xFFFFFFFFFF000, 0x1000)
            e0 = struct.unpack_from("<Q", blk)[0]
            say("[%d] frame OPEN e0=%#x" % (pid, e0))
        except OSError as e:
            stats["faults"] += 1
            say("[%d] frame SHUT %s" % (pid, str(e)[:60]))
        # hop A: the recorded image base
        leaf, nota = walk_bounded(dtb, base, g, stats)
        say("[%d] base walk -> %s (%s)"
            % (pid, ("%#x" % leaf) if leaf else "None", nota))
        if leaf:
            ok_leaf += 1
            try:
                mz = g.read_phys(leaf, 2)
                stats["ok_reads"] += 1
                say("[%d] mz at base leaf = %r" % (pid, mz))
                if mz == b"MZ" and mz_found is None:
                    mz_found = (pid, dtb, base, leaf)
            except OSError as e:
                stats["faults"] += 1
                say("[%d] mz read FAULT %s" % (pid, str(e)[:60]))
        # hop B: a second PT page 3 MB up (exercises different table pages)
        leafb, notb = walk_bounded(dtb, (base + 0x300000) & ~0xFFF, g, stats)
        say("[%d] +3MB walk -> %s (%s)"
            % (pid, ("%#x" % leafb) if leafb else "None", notb))

    faults = stats["faults"]
    say("--- tally: specimens=%d ok_base_leaf=%d ok_reads=%d faults=%d (%.1fs)"
        % (len(specs), ok_leaf, stats["ok_reads"], faults, time.time() - t0))
    say("last_fault=%s" % (stats["last_fault"] or "-"))

    if mz_found:
        say("MZ_EVIDENCE pid=%d dtb=%#x base=%#x leaf=%#x" % mz_found)
        say("VERDICT: MACHINERY_SANE")
        return 0
    if faults >= 2 * max(ok_leaf, 1) or ok_leaf == 0:
        say("VERDICT: FAULT_WEDGE")
        return 4
    say("VERDICT: CONTENT_BLIND")
    return 5


if __name__ == "__main__":
    try:
        rc = main()
    except Exception as e:                               # noqa: BLE001
        import traceback
        say("EXC %r" % e)
        say(traceback.format_exc())
        rc = 9
    say("h412 end rc=%d" % rc)
    sys.exit(rc)

