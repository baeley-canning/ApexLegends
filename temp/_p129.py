r"""_p129.py -- PROBE p129: is the 0x14bc25900..0x14bc2d900 window alive, and what is in it?

p128 killed p127's PASS: the 4 "positions" were byte-identical over 6 s, the names were already
gone from the cluster, and 3362.010/193.298/3654.341 repeat at a 0x210 stride.  That is the shape
of a freed heap block still holding an old copy of a table, not of an entity.

The variable this probe changes: SPAN and ORDER.  p127 read cluster +-0x8000 in one pass and
reported only values that survived a shape test; here the whole window is read as one buffer,
twice, so name, float and change can all be placed on the same address line.

Output is one line per 0x100 byte block: how many bytes changed between the two passes, whether
a name is in that block, and every plausible float triple in it.  A live record shows a block
with a name AND changing bytes close together; a static table shows neither.

Read-only, gdrv3 only.  Writes temp\_p129_out.txt.
RESULT:/VERDICT: name the variable (R5).  Usage: _p129.py
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import gio
import dumplive as dl

OUT = os.path.join(HERE, "_p129_out.txt")
NEEDLES = ["kern30120", "spanner1981", "Gen X Gaming"]
LO = 0x14bc25900
HI = 0x14bc2d900
GAP = 3


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def pl(v):
    return v == v and 1e-6 < abs(v) < 1e7


def grab(g):
    try:
        b = dl.retry_phys(g, LO, HI - LO, tries=3)
    except Exception as e:                                     # noqa: BLE001
        say("read %#x+%#x failed: %s" % (LO, HI - LO, e))
        return None
    return b if len(b) == HI - LO else None


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== p129 window autopsy %s  %#x..%#x (%#x bytes) ==="
        % (time.strftime("%H:%M:%S"), LO, HI, HI - LO))
    pid = dl.find_pid()
    say("game_pid=%s" % pid)
    if pid is None:
        say("RESULT: game_pid=none")
        say("VERDICT: PARTIAL - game not running (R9)")
        return 3
    try:
        g = gio.Gio(chunk=0x100000)
    except OSError as e:
        say("gio: %s" % e)
        return 2

    a = grab(g)
    if a is None:
        say("VERDICT: FAIL - window unreadable")
        return 1
    say("pass1 ok, sleeping %ds" % GAP)
    time.sleep(GAP)
    b = grab(g)
    if b is None:
        say("VERDICT: FAIL - second read of the same window failed")
        return 1

    changed_total = sum(1 for i in range(len(a)) if a[i] != b[i])
    say("changed bytes whole window: %d / %#x" % (changed_total, len(a)))
    say("names anywhere in window: %s"
        % (sorted(n for n in NEEDLES if n.encode("ascii") in a) or "NONE"))

    say("--- per-block ---")
    for base in range(0, len(a), 0x100):
        blk = a[base:base + 0x100]
        ch = sum(1 for i in range(len(blk)) if blk[i] != b[base + i])
        nm = [n for n in NEEDLES if n.encode("ascii") in blk]
        trip = []
        for o in range(0, len(blk) - 11, 4):
            x, y, z = struct.unpack("<fff", blk[o:o + 12])
            if pl(x) and pl(y) and pl(z) and abs(x) < 12000 and abs(y) < 4000 and abs(z) < 12000:
                if abs(x) > 250 or abs(z) > 250:
                    trip.append("%+#x %.2f %.2f %.2f" % (base + o - LO, x, y, z))
        if not ch and not nm and not trip:
            continue
        say("  %+#07x chg=%-4d %s%s"
            % (base - LO, ch, ("NAMES=" + ",".join(nm) + " ") if nm else "",
               " | ".join(trip)))

    say("--- changed field detail (first 40) ---")
    n = 0
    for i in range(0, len(a) - 3, 4):
        if a[i:i + 4] != b[i:i + 4]:
            x, y = struct.unpack("<ff", a[i:i + 4] + b[i:i + 4])
            say("  %+#07x %.4f -> %.4f" % (i - LO, x, y))
            n += 1
            if n >= 40:
                break

    say("RESULT: changed_bytes=%d names_in_window=%d"
        % (changed_total, len([n2 for n2 in NEEDLES if n2.encode("ascii") in a])))
    if changed_total:
        say("VERDICT: PASS - the window is live (%d bytes moved in %ds) - read it as a record"
            % (changed_total, GAP))
    else:
        say("VERDICT: FAIL - window static over %ds: stale copy, re-sweep needed" % GAP)
    return 0


if __name__ == "__main__":
    sys.exit(main())
