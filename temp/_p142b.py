r"""_p142b.py -- is the candidate DTB real?  PML4 self-entry + tight-read liveness, no sleeps.

p142 v3's walk loop sleeps 0.1 s between tries, which is the known poison (a 1450 is a refusal,
not a timeout) - so a live DTB can burn all 12 tries.  This reads the frame with 12 INSTANT
tries, prints the self-referencing PML4 index value and, if the gate holds, builds the Walk.
Read-only, gdrv3.  Writes temp\_p142b_out.txt.
Usage: _p142b.py [--dtb=0x...]
"""
import os
import sys
import threading
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import gio
import dumplive as dl

OUT = os.path.join(HERE, "_p142b_out.txt")
CACHE = os.path.join(HERE, "_dtb.txt")


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def main():
    dtb = 0
    for a in sys.argv:
        if a.startswith("--dtb="):
            dtb = int(a.split("=", 1)[1], 0)
    if not dtb:
        try:
            dtb = int(open(CACHE, "r", encoding="utf-8").read().strip(), 0)
        except (OSError, ValueError):
            say("no dtb")
            return 1
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" --dtb=%#x' % (os.path.abspath(__file__), dtb)))
        return 0
    open(OUT, "w").close()
    say("=== p142b %s dtb=%#x ===" % (time.strftime("%H:%M:%S"), dtb))
    g = gio.Gio(chunk=0x1000)
    ok, last = None, "none"
    for k in range(12):
        try:
            ok = g.read_phys(dtb, 0x1000)
            say("read ok on try %d" % (k + 1))
            break
        except OSError as e:
            last = e
    if ok is None:
        say("12 instant tries all refused: %s" % last)
        say("RESULT: dtb=%#x dead-at-PML4" % dtb)
        say("VERDICT: FAIL - candidate PML4 unreadable")
        return 1
    q = np.frombuffer(ok, "<u8")
    self_i = (dtb >> 39) & 0x1FF
    say("self-index=%d PML4[si]=%#x (frame=%#x) %s"
        % (self_i, int(q[self_i]), dtb,
           "SELF-OK" if (int(q[self_i]) & ~0xFFF) == dtb else "SELF-MISMATCH"))
    nz = np.nonzero(q)[0]
    say("nonzero entries=%d" % len(nz))
    w = None
    for k in range(6):
        try:
            box = {}
            t = threading.Thread(target=lambda: box.update(w=dl.Walk(g, dtb)), daemon=True)
            t.start()
            t.join(20)
            if t.is_alive():
                raise OSError("wedge")
            w = box["w"]
            break
        except OSError as e:
            say("  walk try %d: %s" % (k + 1, e))
    if w is None:
        say("RESULT: dtb=%#x self=%d walk=dead" % (dtb, self_i))
        say("VERDICT: FAIL - PML4 reads but the walk is dead")
        return 1
    say("walk alive")
    say("RESULT: dtb=%#x self=%d nonzero=%d walk=ALIVE" % (dtb, self_i, len(nz)))
    say("VERDICT: PASS - usable DTB (walk responds)")
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
