"""Ladder: is the 1450 refusal a function of the physical address?

Random 2 % does not explain two consecutive DTB frames (13.8 GB, 16.9 GB)
failing while 5 GB reads.  Probe one page per GB, forward then backward, and
re-probe a failing page at the end (does it recover?).
"""
import sys

sys.path.insert(0, "..\\ext")
import gio
import dumplive as dl

OUT = "_ladder_out.txt"
log = open(OUT, "w", encoding="utf-8")


def say(s):
    log.write(s + "\n")
    log.flush()


def probe(g, pa):
    for _k in range(2):
        try:
            g.read_phys(pa, 0x1000)
            return True
        except OSError:
            pass
    return False


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % __file__))
        return 0
    g = gio.Gio(chunk=0x1000)
    addrs = [0x400000 + i * 0x40000000 for i in range(31)]     # 4 MB .. 30 GB
    good, bad = [], []
    for tag, seq in (("fwd", addrs), ("rev", list(reversed(addrs)))):
        line = []
        for pa in seq:
            r = probe(g, pa)
            (good if r else bad).append(pa)
            line.append("%s%dG" % ("+" if r else "-", pa >> 30))
        say("%s: %s" % (tag, " ".join(line)))
    say("distinct good=%d bad=%d" % (len(set(good)), len(set(bad))))
    if bad:
        p = bad[0]
        say("re-probe %#x (%.1f GB): %s" % (p, p / 1e9, "RECOVERED" if probe(g, p) else "still dead"))
    hi_good = max(good) if good else 0
    lo_bad = min(bad) if bad else 0
    say("highest good=%#x lowest bad=%#x" % (hi_good, lo_bad))
    say("RESULT: good=%d bad=%d" % (len(set(good)), len(set(bad))))
    say("VERDICT: %s" % ("PASS - reads work in both directions"
                         if len(set(good)) > len(set(bad)) else "FAIL - mostly dead"))
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
