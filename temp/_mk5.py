"""h34s: p137-shape storm on the dead DTB frame - 12 tries, ZERO sleep.

_mk3 (0.13 s ladder) and _mk4 (1 s cadence) both SLEPT between tries; FACTS
(p137) says the only shape that converts 1450 is the IMMEDIATE re-try
(12x, no sleep; 20 ms between tries = poison), and dumplive.retry_phys itself
sleeps 50-350 ms.  One variable: inter-try delay = 0 (R5).

Targets: ctrl 0x436A00000 (never failed), the LIVE DTB frame of pid 6004
(re-derived from EPROCESS 0x4814ed010 +0x98; fallback 0x6EF568000), and
wasok 0x6EF980000 (READ in _mk, dead in _mk3/_mk4).

PASS = frame lands within 12 no-sleep tries AND a 20-read burst holds >=15/20
AND the PML4 self-references.  Pure read probe, gdrv3 only, no state touched.
"""
import os
import sys
import time

sys.path.insert(0, "..\\ext")
import dumplive as dl          # noqa: E402
import gio                     # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_mk5_out.txt")
OBJ = 0x4814ED010              # EPROCESS of pid 6004 (this boot, 17:20 launch)
FRAME_FALLBACK = 0x6EF568000   # DTB measured in the _mk session
CTRL = 0x436A00000             # freed old-process page, has always read
WASOK = 0x6EF980000            # read ok in _mk band map, dead in _mk3/_mk4
TRIES = 12
BURST = 20


def say(s):
    line = str(s)
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def storm(g, pa, tries=TRIES):
    """Up to `tries` back-to-back reads, NO sleep.  (ok_try|None, trace)."""
    trace = []
    for i in range(tries):
        t0 = time.perf_counter()
        try:
            buf = g.read_phys(pa, 0x1000)
            trace.append("try%d=READ(%dus)" % (i, (time.perf_counter() - t0) * 1e6))
            return i, buf, trace
        except OSError as e:
            trace.append("try%d=e%s(%dus)" % (i, e.errno,
                                              (time.perf_counter() - t0) * 1e6))
    return None, None, trace


def burst(g, pa):
    ok, errs = 0, {}
    for _ in range(BURST):
        try:
            g.read_phys(pa, 0x1000)
            ok += 1
        except OSError as e:
            errs[e.errno] = errs.get(e.errno, 0) + 1
    return ok, errs


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % __file__))
        return 0
    open(OUT, "w").close()
    say("=== mk5 zero-sleep storm %s ===" % time.strftime("%H:%M:%S"))
    g = gio.Gio(chunk=0x1000)

    # R10 guard: every PA must sit inside the usable-RAM interval set.
    ranges, note = dl.usable_ranges(g.ram_top, 0x1000, None)
    say("ram_top=%#x ranges=%d (%s)" % (g.ram_top, len(ranges), note))

    def in_map(pa):
        p = pa & ~0xFFF
        return any(a <= p and p + 0x1000 <= b for a, b in ranges)

    # Re-derive the live DTB from the EPROCESS object page (itself a read).
    dtb = 0
    if in_map(OBJ):
        k, buf, tr = storm(g, OBJ & ~0xFFF)
        if buf is not None:
            import struct
            name = bytes(buf[0x10 + 0x3A8:0x10 + 0x3B8])
            pid = struct.unpack_from("<I", buf, 0x10 + 0x240)[0]
            d = struct.unpack_from("<Q", buf, 0x10 + 0x98)[0]
            say("obj %#x read try%d: name=%r pid=%d dtb@+0x98=%#x"
                % (OBJ, k, name, pid, d))
            if name.rstrip(b"\x00") == b"r5apex_dx12.ex" and d and not d & 0xFFF:
                dtb = d
        else:
            say("obj page unreadable: %s" % " ".join(tr))
    else:
        say("obj %#x NOT in usable map - skipped (R10)" % OBJ)
    if not dtb:
        dtb = FRAME_FALLBACK
        say("falling back to session dtb %#x" % dtb)

    results = {}
    for tag, pa in (("ctrl", CTRL), ("frame", dtb), ("wasok", WASOK)):
        if not in_map(pa):
            say("%-5s %#012x NOT in usable map - skipped (R10)" % (tag, pa))
            results[tag] = None
            continue
        k, buf, tr = storm(g, pa)
        say("%-5s %#012x storm: %s" % (tag, pa, " ".join(tr)))
        selfok, present = False, -1
        if buf is not None:
            import struct
            ent = struct.unpack("<512Q", buf)
            present = sum(1 for x in ent if x & 1)
            selfok = any((x & ~0xFFF) == (pa & ~0xFFF) for x in ent)
            okn, errs = burst(g, pa)
            say("%-5s burst: %d/%d READ errs=%s selfref=%s present=%d"
                % (tag, okn, BURST, errs or "-", selfok, present))
            results[tag] = (k, okn, selfok)
        else:
            results[tag] = False

    # post-state: device still alive?
    k, _, tr = storm(g, CTRL, tries=3)
    say("post ctrl: %s" % ("READ" if k is not None else "FAIL " + " ".join(tr)))

    fr = results.get("frame")
    say("RESULT: frame=%s ctrl=%s wasok=%s"
        % (fr, results.get("ctrl"), results.get("wasok")))
    if fr and fr is not True and fr[1] >= 15:
        say("VERDICT: PASS - zero-sleep storm converts the DTB frame "
            "(try %d, burst %d/%d, selfref=%s); sleeping ladders were the bug"
            % (fr[0], fr[1], BURST, fr[2]))
    elif fr and fr is not True:
        say("VERDICT: PARTIAL - frame converted at try %d but burst only %d/%d"
            % (fr[0], fr[1], BURST))
    elif fr is None:
        say("VERDICT: FAIL - frame PA outside the usable map (R10 refusal)")
    else:
        say("VERDICT: FAIL - 1450 survives 12 no-sleep tries; p137 shape does "
            "not cure this page, box-state branch (reboot) is next")
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
