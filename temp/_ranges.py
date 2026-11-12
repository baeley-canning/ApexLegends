"""Where does the 1450 come from?  Print the usable-range plan and locate the two
persistent bad frames (0x400000, 0x436ad8000) inside or outside it, then probe each
range's first/last page to see whether the refusals track range edges.
"""
import sys

sys.path.insert(0, "..\\ext")
import gio
import dumplive as dl

OUT = "_ranges_out.txt"
log = open(OUT, "w", encoding="utf-8")


def say(s):
    log.write(s + "\n")
    log.flush()


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % __file__))
        return 0
    g = gio.Gio(chunk=0x1000)
    ranges, note = dl.usable_ranges(g.ram_top, 0x1000, None)
    say("ram_top=%#x note=%s" % (g.ram_top, note))
    for lo, hi in ranges:
        say("range %#x-%#x  %.2f GB" % (lo, hi, (hi - lo) / 1e9))
    for pa in (0x400000, 0x436ad8000):
        inside = [(lo, hi) for lo, hi in ranges if lo <= pa < hi]
        say("probe-target %#x inside=%s" % (pa, inside or "NO-RANGE"))
    bad_total = 0
    for lo, hi in ranges:
        for lbl, pa in (("lo", lo), ("hi", hi - 0x1000)):
            r = False
            for _k in range(3):
                try:
                    g.read_phys(pa, 0x1000)
                    r = True
                    break
                except OSError:
                    pass
            bad_total += 0 if r else 1
            say("  edge %s %#x: %s" % (lbl, pa, "ok" if r else "1450"))
    say("RESULT: edge fails=%d of %d" % (bad_total, 2 * len(ranges)))
    say("VERDICT: %s" % ("PASS - edges readable" if bad_total == 0 else "PARTIAL - edge refusals"))
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
