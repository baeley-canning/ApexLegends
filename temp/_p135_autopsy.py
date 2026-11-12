r"""_p135_autopsy.py -- dump the neighbourhood of a p134 seed and name the record.

p134 (full census, 11.6 + 12.6 GB, 2.5M/5.2M candidates) passed with 24 coherent stops in
two families: a bone block at x~4180-4231 / x~6213 mirrored at exactly +0x30000, and x~-8400
copies in six unrelated heaps.  Everything here is a DUMP plus a few cheap indexes; naming
happens offline from the file.

Per seed:
  1. f32 + i32 lanes over seed-0x800..seed+0x800 with address column
  2. hp/shield marker scan (100/75/50/25/3000/2500/2250/2000 as i32) in that window
  3. stride walk 0xC0/0xC8/0x400 both ways listing plausible triples with delta from seed
  4. TWIN DIFF against the byte at +0x30000: runs of >=16 identical bytes = the duplicated
     record's extent, which is the stride and the record start handed to us for free
  5. qwords in a RAM range (pointer-looking) with their offsets
Read-only, gdrv3, 12-try immediate retry (p137: 1450 is a refusal, not a timeout).
Writes temp\_p135_autopsy.txt.  Usage: _p135_autopsy.py [--seed=0x..]...
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

OUT = os.path.join(HERE, "_p135_autopsy.txt")
WIN = 0x800
TWIN = 0x30000
STRIDES = (0xC0, 0xC8, 0x400)
MARKERS = (100, 75, 50, 25, 3000, 2500, 2250, 2000, 150)
F32 = np.dtype("<f4")
I32 = np.dtype("<i4")
SEEDS = [0x5557d230c, 0x5e3429b6c]


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
                box["e"] = e
                if k == 5:
                    time.sleep(0.002)

    t = threading.Thread(target=work, daemon=True)
    t.start()
    t.join(secs)
    if t.is_alive():
        return None, "wedge"
    if "b" not in box:
        return None, str(box.get("e"))
    return box["b"], None


def plausible(v):
    return np.isfinite(v) & (np.abs(v) > 1e-6) & (np.abs(v) < 1e7)


def main():
    seeds = list(SEEDS)
    for a in sys.argv:
        if a.startswith("--seed="):
            v = int(a.split("=", 1)[1], 0)
            if v not in seeds:
                seeds.insert(0, v)
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== p135 autopsy %s seeds=%s win=%#x twin=%#x ==="
        % (time.strftime("%H:%M:%S"), ",".join("%#x" % s for s in seeds), WIN, TWIN))
    g = gio.Gio(chunk=0x1000)
    say("ram_top=%#x" % g.ram_top)
    for seed in seeds:
        say("")
        say("### seed %#x" % seed)
        b, err = rd(g, seed - WIN, 2 * WIN)
        if not b:
            say("read failed: %s" % err)
            continue
        base = seed - WIN
        v = np.frombuffer(b, F32)
        iv = np.frombuffer(b, I32)
        t, err2 = rd(g, seed + TWIN - WIN, 2 * WIN)
        say("twin read %s" % ("FAILED " + err2 if not t else "ok"))

        say("-- markers (i32) --")
        for m in MARKERS:
            hits = np.nonzero(iv == m)[0]
            if len(hits):
                say("  %5d: %s" % (m, " ".join("%+d" % (h * 4 - WIN) for h in hits[:8])))
        say("-- plausible triples on strides --")
        pv = plausible(v)
        tri = pv[:-2] & pv[1:-1] & pv[2:]
        for st in STRIDES:
            e = st // 4
            for sgn in (1, -1):
                hits = []
                for i in np.nonzero(tri)[0]:
                    off = i * 4 - WIN
                    q = off + sgn * st
                    if abs(q) <= WIN - 12:
                        j = (q + WIN) // 4
                        if 0 <= j < len(v) - 2 and tri[j]:
                            hits.append(q)
                if hits:
                    say("  %+4d %d hits: %s" % (sgn * st, len(hits),
                                                " ".join("%+d" % h for h in hits[:12])))
        if t:
            eq = np.frombuffer(b, np.uint8) == np.frombuffer(t, np.uint8)
            say("-- twin identical runs (>=16 B) --")
            runs = 0
            i = 0
            while i < len(eq):
                if eq[i]:
                    j = i
                    while j < len(eq) and eq[j]:
                        j += 1
                    if j - i >= 16:
                        runs += 1
                        if runs <= 20:
                            say("  %+6d len=%#x" % (i - WIN, j - i))
                    i = j
                else:
                    i += 1
            say("  runs=%d" % runs)
        say("-- pointer-looking qwords --")
        q = np.frombuffer(b, "<u8")
        pl = np.nonzero((q > 0x10000) & (q < g.ram_top) & (q % 0x10 == 0))[0]
        for k in pl[:24]:
            say("  %+6d %#x" % (k * 8 - WIN, q[k]))
        with open(os.path.join(HERE, "_p135_hex_%x.txt" % seed), "a") as f:
            for r in range(0, len(b), 64):
                fl = " ".join("%9.3g" % x for x in v[r // 4:(r + 64) // 4])
                f.write("%+6d %s\n" % (r - WIN, fl))
    g.close()
    say("RESULT: dumped %d seed(s)" % len(seeds))
    return 0


if __name__ == "__main__":
    sys.exit(main())
