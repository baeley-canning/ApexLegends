r"""_p142c.py -- which name hit is the LIVE process, and is its DTB readable?

p142 v3's only candidate DTB (0x33bcb0000) refuses every read, including 12 instantaneous
tries, so either the driver is refusing globally again or `candidates_for` gated a stale
EPROCESS.  This separates those two cases: generic liveness reads first, then per hit the
UniqueProcessId scan (value == the live pid found by dumplive) around the ImageFileName, then
the DTB stored at EPROCESS+0x28.
Read-only, gdrv3.  Writes temp\_p142c_out.txt.
Usage: _p142c.py [--hits=0x...,0x...]
"""
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import gio
import dumplive as dl

OUT = os.path.join(HERE, "_p142c_out.txt")
HITS = (0x162dfc6f0, 0x47c41d3b8)


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def tries(g, pa, n=0x1000, k=12):
    err = "none"
    for _ in range(k):
        try:
            return g.read_phys(pa, n), None
        except OSError as e:
            err = e
    return None, err


def main():
    try:
        return body()
    except Exception:
        import traceback
        say("EXC: " + traceback.format_exc().replace("\n", " | "))
        return 9


def body():
    hits = list(HITS)
    for a in sys.argv:
        if a.startswith("--hits="):
            hits = [int(x, 0) for x in a.split("=", 1)[1].split(",") if x]
    if not dl.elevation():
        open(OUT, "w").close()
        return dl.run_elevated('"%s"' % os.path.abspath(__file__))
    open(OUT, "w").close()
    say("=== p142c %s hits=%s ===" % (time.strftime("%H:%M:%S"), ",".join("%#x" % h for h in hits)))
    pid = dl.find_pid()
    say("live_pid=%s" % pid)
    g = gio.Gio(chunk=0x1000)
    for pa in (0x1000, 0x100000, hits[0] if hits else 0x1000):
        _b, e = tries(g, pa)
        say("liveness %#x -> %s" % (pa, e or "ok"))
    for h in hits:
        say("hit %#x" % h)
        obj = h - 0x338                      # ImageFileName is 0x338 into EPROCESS
        b, e = tries(g, obj, 0x500)
        if not b:
            say("  object unreadable: %s" % e)
            continue
        q = np.frombuffer(b, "<u8")
        say("  name=%r  head: %s"
            % (b[0x338:0x348].split(b"\x00")[0],
               " ".join("%#x" % int(x) for x in q[:6])))
        say("  +0x28 dtb=%#x  +0x440 pid=%#x (live %s)"
            % (int(q[5]), int(q[0x88]), pid))
        d = int(q[5])
        if d:
            _b2, e2 = tries(g, d & ~0xFFF)
            say("  dtb %#x read -> %s" % (d & ~0xFFF, e2 or "ok"))
    g.close()
    say("RESULT: hits=%d" % len(hits))
    return 0


if __name__ == "__main__":
    sys.exit(main())
