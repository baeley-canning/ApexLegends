"""mk15: 1450-onset timer - how long do a fresh process's page tables stay
readable before gdrv3 starts refusing them?

mk13's law: live page-table pages refuse gdrv3 reads, freed ones read.  The
onset is DELAYED: pid 26496's DTB (allocated 23:10) was dead by 23:24, and a
17:5x-live frame was dead by 18:0x.  Transport fork (A) - snapshot the table
hierarchy at launch - lives or dies by this window.  Measure it with
sacrificial, windowless children (pythonw), never the game.

Method: spawn 3 pythonw children, find their EPROCESSes (targeted sweep of the
4-8 GiB pool band where tonight's EPROCESSes clustered, full plan as fallback),
then storm every child DTB + the game's dtb_new + ctrl every 10 s for 25 min.
Onset per child = first round its DTB refuses 6/6 tries.  R4: children are
killed at the end (they are ours).  Read-only otherwise.  _mk15_out.txt.
"""
import os
import struct
import subprocess
import sys
import time

os.environ["GIO_DST_LAST"] = "1"

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))
import gio                     # noqa: E402
import dumplive as dl          # noqa: E402

OUT = os.path.join(HERE, "_mk15_out.txt")
PAGE = 0x1000
NEEDLE = b"pythonw.exe"
GAME_DTB = 0x5732E3000
CTRL = 0x436A00000
BAND = [(0x100000000, 0x200000000)]      # tonight's EPROCESS cluster band
ROUNDS = 150                              # 150 x 10 s = 25 min
GAP = 10.0


def say(s):
    line = str(s)
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def find_children_dtbs(g, ranges, pids):
    found = {}

    def in_map(pa):
        p = pa & ~0xFFF
        return any(a <= p and p + PAGE <= b for a, b in ranges)

    def sweep(plan):
        for rlo, rhi in plan:
            pa = rlo
            carry = b""
            while pa < rhi and len(found) < len(pids):
                n = min(0x100000, rhi - pa)
                try:
                    buf = g.read_phys(pa, n)
                except OSError:
                    parts = []
                    p = pa
                    while p < pa + n:
                        m = min(PAGE, pa + n - p)
                        try:
                            parts.append(g.read_phys(p, m))
                        except OSError:
                            parts.append(b"\x00" * m)
                        p += m
                    buf = b"".join(parts)
                data = carry + buf
                base = pa - len(carry)
                i = data.find(NEEDLE)
                while i >= 0:
                    h = base + i
                    obj = h - 0x3A8
                    page = obj & ~0xFFF
                    o = obj - page
                    if obj > 0 and o + 0x3C0 <= PAGE and in_map(page) \
                            and obj not in found:
                        try:
                            pb = g.read_phys(page, PAGE)
                            pid32 = struct.unpack_from("<I", pb, o + 0x240)[0]
                            dtb = struct.unpack_from("<Q", pb, o + 0x98)[0]
                            if pb[o + 0x3A8:o + 0x3A8 + len(NEEDLE)] == NEEDLE \
                                    and pid32 in pids and dtb \
                                    and not dtb & 0xFFF and in_map(dtb):
                                found[obj] = (pid32, dtb & ~0xFFF)
                                say("VALID child obj %#x pid=%d dtb=%#x"
                                    % (obj, pid32, dtb))
                        except OSError:
                            pass
                    i = data.find(NEEDLE, i + 1)
                carry = data[-(len(NEEDLE) - 1):]
                pa += n

    sweep(BAND)
    if len(found) < len(pids):
        say("band sweep found %d/%d - widening to full plan"
            % (len(found), len(pids)))
        sweep(ranges)
    return found


def storm6(g, pa):
    for _ in range(6):
        try:
            g.read_phys(pa, PAGE)
            return True
        except OSError:
            pass
    return False

def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== mk15 onset timer %s ===" % time.strftime("%H:%M:%S"))

    t_spawn = time.time()
    kids = []
    for _ in range(3):
        kids.append(subprocess.Popen(
            [sys.executable.replace("python.exe", "pythonw.exe"),
             "-c", "import time; time.sleep(3600)"],
            creationflags=0x08000000))          # CREATE_NO_WINDOW
    pids = {k.pid for k in kids}
    say("spawned children pids=%s at t=0" % sorted(pids))

    g = gio.Gio(chunk=0x100000)
    ranges, note = dl.usable_ranges(g.ram_top, None, None, [])
    say("ram_top=%#x ranges=%d (%s)" % (g.ram_top, len(ranges), note))
    time.sleep(5)                               # let EPROCESS/tables settle
    found = find_children_dtbs(g, ranges, pids)
    say("sweep done at t=%.0fs: %d/%d children located"
        % (time.time() - t_spawn, len(found), len(pids)))
    if not found:
        say("RESULT: no child EPROCESS found")
        say("VERDICT: PARTIAL - sweep missed (band theory wrong?)")
        for k in kids:
            k.kill()
        g.close()
        return 1

    targets = [("c%d" % i, dtb) for i, (obj, (pid, dtb))
               in enumerate(sorted(found.items()))]
    targets += [("game", GAME_DTB), ("ctrl", CTRL)]
    onsets = {}
    t0 = time.time()
    for r in range(ROUNDS):
        row = []
        for tag, pa in targets:
            ok = storm6(g, pa)
            row.append("%s=%s" % (tag, "R" if ok else "."))
            if not ok and tag.startswith("c") and tag not in onsets:
                onsets[tag] = time.time() - t_spawn
                say("*** ONSET %s dtb=%#x dead at t=%.0fs (%.1f min) ***"
                    % (tag, pa, onsets[tag], onsets[tag] / 60))
        say("t=%4.0fs %s" % (time.time() - t0, " ".join(row)))
        if len(onsets) == sum(1 for t, _ in targets if t.startswith("c")):
            say("all child DTBs dead - stopping early at t=%.0fs"
                % (time.time() - t0))
            break
        time.sleep(GAP)

    for k in kids:
        try:
            k.kill()
        except OSError:
            pass
    say("children killed (R4)")
    got = sorted(onsets.values())
    say("RESULT: onsets=%s (s)" % (["%.0f" % x for x in got] or "none"))
    if got:
        say("VERDICT: onset window min=%.0fs median=%.0fs max=%.0fs - a "
            "launch snapshot must finish in <%.0fs"
            % (got[0], got[len(got) // 2], got[-1], got[0]))
    else:
        say("VERDICT: no onset in %d min - tables of small processes stay "
            "readable; game's early death may be allocation-driven, re-test "
            "with a fat child" % (ROUNDS * int(GAP) // 60))
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())