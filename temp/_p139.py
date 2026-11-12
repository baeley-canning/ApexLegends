r"""_p139.py -- is the c0/c1 family live, and which lanes move?

p135 showed the buffer under a seed is rewritten every frame (addresses that read one triple
in pass2 held a different row two minutes later), so one dump cannot separate live pose lanes
from bind data.  This probe samples every candidate twice, 1.5 s apart, and reports which
4-byte lanes CHANGED: live fields change, bind/constant data does not.  It also prints the
triple so a world-plausible one (|mid| < 4000, |x| and |z| > 250) can be spotted directly.

Candidates: the four c0 and four c1 seeds (world-like, bone-height spread) plus one c2 seed.
Read-only, gdrv3, 12-try immediate retry.  Writes temp\_p139_out.txt.
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

OUT = os.path.join(HERE, "_p139_out.txt")
WIN = 0x200
GAP = 1.5
F32 = np.dtype("<f4")
ADDRS = [0x5557d230c, 0x5557d2a08, 0x5557d2960, 0x5557d293c,
         0x5558024d4, 0x555802a5c, 0x555802528, 0x5557d2924,
         0x5e3429b6c]


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def rd(g, pa, n, secs=4.0):
    box = {}

    def work():
        for k in range(12):
            try:
                box["b"] = g.read_phys(pa, n)
                return
            except OSError as e:
                box["e"] = repr(e)
                if k == 5:
                    time.sleep(0.002)

    t = threading.Thread(target=work, daemon=True)
    t.start()
    t.join(secs)
    if t.is_alive():
        return None, "wedge"
    if "b" not in box:
        return None, box.get("e", "no-attempt")
    return box["b"], None


def main():
    addrs = list(ADDRS)
    for a in sys.argv:
        if a.startswith("--at="):
            addrs.insert(0, int(a.split("=", 1)[1], 0))
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== p139 liveness %s win=%#x gap=%.1fs ===" % (time.strftime("%H:%M:%S"), WIN, GAP))
    g = gio.Gio(chunk=0x1000)
    first = {}
    for a in addrs:
        b, err = rd(g, a, WIN)
        first[a] = b
        if not b:
            say("%#011x: read failed %s" % (a, err))
    time.sleep(GAP)
    for a in addrs:
        b1 = first.get(a)
        b2, err = rd(g, a, WIN)
        if not b2:
            say("%#011x: second read failed %s" % (a, err))
            continue
        v = np.frombuffer(b2, F32)
        t = (float(v[0]), float(v[1]), float(v[2]))
        world = (abs(t[1]) < 4000 and abs(t[0]) > 250 and abs(t[2]) > 250)
        say("")
        say("%#011x triple=%.2f %.2f %.2f%s" % (a, t[0], t[1], t[2],
                                                "  WORLD-LIKE" if world else ""))
        if not b1:
            continue
        q1 = np.frombuffer(b1, "<u4")
        q2 = np.frombuffer(b2, "<u4")
        ch = np.nonzero(q1 != q2)[0]
        say("  changed lanes=%d of %d" % (len(ch), len(q1)))
        for k in ch[:40]:
            f1 = np.frombuffer(b1, F32)[k]
            say("    %+#6d  %10.4g -> %10.4g" % (k * 4 - 0, f1, v[k]))
    g.close()
    say("")
    say("RESULT: sampled %d addr(s)" % len(addrs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
