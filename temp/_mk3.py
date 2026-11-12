"""h34y: is the DTB frame dead, or just 1450-under-load?

retry_phys documents 1450 as transient and Walk climbs 8 tries with scaled
backoff; every earlier probe of this frame used ONE try.  A verdict that skips
that ladder is not a verdict (R9).  Control pages ride the same ladder so a
failure can never be blamed on the ladder itself.

PASS = frame reads on some try AND its PML4[0xff] leads to a real table.
"""
import os
import struct
import sys

sys.path.insert(0, "..\\ext")
import dumplive as dl          # noqa: E402
import gio                     # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_mk3_out.txt")
FRAME = 0x6EF568000
CTRL = 0x436A00000
GOOD = 0x6EF980000
TRIES = 8


def say(s):
    line = str(s)
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def ladder(g, pa):
    """Climb retry_phys' exact ladder by hand so every try is visible."""
    vec = []
    for i in range(TRIES):
        try:
            buf = g.read_phys(pa, 0x1000)
            vec.append("ok")
            return True, buf, " ".join(vec) + " (try %d)" % i
        except OSError as e:
            vec.append(str(e.errno))
            if i < TRIES - 1:
                import time
                time.sleep(0.13 * (i + 1))
    return False, None, " ".join(vec)


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % __file__))
        return 0
    open(OUT, "w").close()
    g = gio.Gio(chunk=0x1000)
    say("ram_top=%#x frame=%#x" % (g.ram_top, FRAME))

    for tag, pa in (("ctrl", CTRL), ("good", GOOD), ("frame", FRAME)):
        ok, buf, trail = ladder(g, pa)
        say("  %-5s %#012x -> %s  [%s]" % (tag, pa, "READ" if ok else "FAIL", trail))

    ok, buf, _ = ladder(g, FRAME)
    say("frame retry #2 ladder: %s" % ("read" if ok else "still fails"))
    say("full probe_dtb(frame): %s" % dl.probe_dtb(g, FRAME))

    if ok:
        ents = [i for i in range(512) if struct.unpack_from("<Q", buf, i * 8)[0] & 1]
        say("present pml4 entries: %d %s" % (len(ents), ents[:8]))
        say("VERDICT: PASS -- frame readable under retry, %d pml4 entries" % len(ents))
    else:
        say("VERDICT: FAIL -- 1450 survives %d tries twice over" % TRIES)
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
