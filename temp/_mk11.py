"""mk11: PFN-lottery verifier for the fresh game instance (pid from find_pid).

_p142 --cal on the 23:10 launch never had a chance: its name sweep uses a
111-byte zero-padded needle AND subtracts the p36/38 BADPA list, and the cal
block then derives obj with a stale nameoff=0x800 (layout constants predate
today's +0x3A8/+0x240/+0x98 map).  Its FAIL says nothing about the new DTB.

This probe runs the _mk5-verified recipe end to end against the LIVE pid:
  1. sweep ALL declared RAM (bad=[] - BADPA is a probe-failure list, not MMIO,
     so skipping it stays R10-safe) for the 14-byte name needle, salvaging
     4 KiB pages out of any dead 1 MiB chunk (dead pages -> census);
  2. for every hit, try both EPROCESS layouts (name+0x3A8/DTB+0x98 and the
     older +0x338/+0x28 pair), validate pid32@+0x240 == live pid;
  3. storm each validated DTB frame: 12 zero-sleep tries, 20-burst, selfref.

One variable (R5): the process (and with it the table PFNs) is fresh.
PASS = live EPROCESS found AND its DTB frame reads >=15/20 AND self-references.
Read-only, gdrv3 only.  Writes _mk11_out.txt.
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))
import dumplive as dl          # noqa: E402
import gio                     # noqa: E402

OUT = os.path.join(HERE, "_mk11_out.txt")
NEEDLE = b"r5apex_dx12.ex"                    # 14 bytes, no padding requirement
LAYOUTS = ((0x3A8, 0x98), (0x338, 0x28))      # (name_off, dtb_off); pid @+0x240
PID_OFF = 0x240
CHUNK = 0x100000
CTRL = 0x436A00000                            # never-failed witness page
TRIES = 12
BURST = 20


def say(s):
    line = str(s)
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def storm(g, pa, tries=TRIES):
    trace = []
    for i in range(tries):
        try:
            buf = g.read_phys(pa, 0x1000)
            trace.append("try%d=READ" % i)
            return i, buf, trace
        except OSError as e:
            trace.append("try%d=e%s" % (i, e.errno))
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
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== mk11 PFN-lottery verifier %s ===" % time.strftime("%H:%M:%S"))

    pid = dl.find_pid()
    say("game_pid=%s" % pid)
    if pid is None:
        say("RESULT: no game")
        say("VERDICT: PARTIAL - game not running (R9)")
        return 3

    g = gio.Gio(chunk=CHUNK)
    ranges, note = dl.usable_ranges(g.ram_top, None, None, [])  # BADPA bypassed
    total = sum(b - a for a, b in ranges)
    say("ram_top=%#x ranges=%d (%s, bad bypassed) plan=%.2f GiB"
        % (g.ram_top, len(ranges), note, total / 2**30))

    def in_map(pa):
        p = pa & ~0xFFF
        return any(a <= p and p + 0x1000 <= b for a, b in ranges)

    # pre-state witness (R3)
    k, _, tr = storm(g, CTRL, tries=3)
    say("pre ctrl %#x: %s" % (CTRL, "READ" if k is not None else
                              "FAIL " + " ".join(tr)))

    # ---- sweep: 1 MiB chunks, 4 KiB salvage, dead-page census -------------
    hits = []
    dead = []
    t0 = time.perf_counter()
    scanned = 0
    for rlo, rhi in ranges:
        pa = rlo
        carry = b""
        while pa < rhi:
            n = min(CHUNK, rhi - pa)
            try:
                buf = g.read_phys(pa, n)
            except OSError:
                parts = []
                p = pa
                while p < pa + n:
                    m = min(0x1000, pa + n - p)
                    try:
                        parts.append(g.read_phys(p, m))
                    except OSError:
                        dead.append(p)
                        parts.append(b"\x00" * m)
                    p += m
                buf = b"".join(parts)
            data = carry + buf
            i = data.find(NEEDLE)
            while i >= 0:
                hits.append(pa - len(carry) + i)
                i = data.find(NEEDLE, i + 1)
            carry = data[-(len(NEEDLE) - 1):]
            scanned += n
            pa += n
    say("sweep done: %.1f GiB in %ds, name_hits=%d dead_pages=%d"
        % (scanned / 2**30, time.perf_counter() - t0, len(hits), len(dead)))
    for p in dead[:48]:
        say("  dead page %#012x%s" % (p, " (known family)" if p in
            (0x436AD8000, 0x6EF568000, 0x6EF980000) else ""))
    if len(dead) > 48:
        say("  ... +%d more dead pages" % (len(dead) - 48))
    # ---- validate each hit against the EPROCESS layouts -------------------
    found = []           # (obj, layout, dtb)
    for h in hits:
        for li, (no, do) in enumerate(LAYOUTS):
            obj = h - no
            if obj < 0x1000:
                continue
            page = obj & ~0xFFF
            if not in_map(page):
                say("hit %#x layout%d: obj %#x outside map (R10 skip)"
                    % (h, li, obj))
                continue
            try:
                pbuf = g.read_phys(page, 0x1000)
            except OSError as e:
                say("hit %#x layout%d: obj page %#x DEAD e%s"
                    % (h, li, page, e.errno))
                continue
            o = obj - page
            if o + max(no, do, PID_OFF) + 16 > 0x1000:
                say("hit %#x layout%d: fields cross page, skipped" % (h, li))
                continue
            nm = pbuf[o + no:o + no + len(NEEDLE)]
            pid32 = struct.unpack_from("<I", pbuf, o + PID_OFF)[0]
            q240 = struct.unpack_from("<Q", pbuf, o + PID_OFF)[0]
            dtb = struct.unpack_from("<Q", pbuf, o + do)[0]
            tag = b"Proc" in pbuf
            ok = (nm == NEEDLE and pid32 == pid and dtb and not dtb & 0xFFF
                  and in_map(dtb))
            say("hit %#x layout%d obj %#x: name=%r pid32=%s dtb=%#x tag=%s "
                "q240=%#x -> %s" % (h, li, obj, nm, pid32, dtb, tag, q240,
                                    "VALID" if ok else "reject"))
            if ok and all(obj != f[0] for f in found):
                found.append((obj, li, dtb))

    # ---- storm the validated DTB frame(s) ---------------------------------
    frame_res = None
    for obj, li, dtb in found:
        frame = dtb & ~0xFFF
        k, buf, tr = storm(g, frame)
        say("frame %#012x (obj %#x L%d) storm: %s" % (frame, obj, li,
                                                      " ".join(tr)))
        if buf is None:
            frame_res = False
            continue
        ent = struct.unpack("<512Q", buf)
        present = sum(1 for x in ent if x & 1)
        selfok = any((x & ~0xFFF) == frame for x in ent)
        okn, errs = burst(g, frame)
        say("frame burst: %d/%d READ errs=%s selfref=%s present=%d"
            % (okn, BURST, errs or "-", selfok, present))
        frame_res = (okn, selfok)

    # post-state witness (R3)
    k, _, tr = storm(g, CTRL, tries=3)
    say("post ctrl: %s" % ("READ" if k is not None else
                           "FAIL " + " ".join(tr)))

    say("RESULT: pid=%d hits=%d valid=%d dead_pages=%d frame=%s"
        % (pid, len(hits), len(found), len(dead), frame_res))
    if frame_res and frame_res is not True and frame_res[0] >= 15:
        say("VERDICT: PASS - lottery won: pid %d DTB %#x reads %d/%d, "
            "selfref=%s; M1 transport gate clears"
            % (pid, found[0][2], frame_res[0], BURST, frame_res[1]))
    elif found:
        say("VERDICT: FAIL - live EPROCESS found but fresh DTB frame is on "
            "the dead set; PFN lottery FALSIFIED")
    elif hits:
        say("VERDICT: PARTIAL - name hits but none validated as pid %d "
            "(see reject lines)" % pid)
    else:
        say("VERDICT: PARTIAL - zero name hits: live EPROCESS page dead or "
            "outside plan; census above")
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())