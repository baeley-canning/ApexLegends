"""Offline check of the p104 PINNED_FAULT handling (no device needed).

Exercises dumplive.in_bad / load_bad against the real badpa file and pid_scan
against a fake Gio, so the hop, the skip and the SCANSTOP verdict are proven
before anything touches the host driver.
"""
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))
os.environ["DUMP_PROG"] = "_p106_prog.txt"
import dumplive as dl  # noqa: E402
import p72_ppath as pp  # noqa: E402

PAGE = 0x1000
PID = 12092
PAT = struct.pack("<Q", PID)
FAIL = []


def check(name, cond, extra=""):
    print("%-46s %s %s" % (name, "PASS" if cond else "FAIL", extra))
    if not cond:
        FAIL.append(name)


# --- the list itself -------------------------------------------------------
bad = dl.load_bad()
check("badpa parses despite the comment line", len(bad) > 0, "ranges=%d" % len(bad))
# The file's 2 MiB grid covers 0x0-0x2000000 outright, so the pinned page *and*
# its neighbour are already known-bad; 0x2000000 is the first clean PA above it.
check("pinned page 0x200000 is known-bad", dl.in_bad(0x200000))
check("0x201000 is known-bad (grid bracket)", dl.in_bad(0x201000))
check("0x1fffff edge is known-bad", dl.in_bad(0x1FFFFF))
check("0x2000000 is past the grid", not dl.in_bad(0x2000000))
check("0x3000000 is not known-bad", not dl.in_bad(0x3000000))
check("the pin's explicit range ends at 0x201000",
      any(a == 0x200000 and b == 0x201000 for a, b in bad))


class Fake(object):
    """Fake Gio: a chunk read fails if any page in it is in `dead`, page reads
    fail for dead pages and return a page carrying the pid otherwise."""

    def __init__(self, dead=(), at=0x40, span=PAGE):
        self.dead = set(dead)
        self.at = at
        self.span = span
        self.reads = []

    def read_phys(self, pa, n):
        self.reads.append((pa, n))
        for off in range(0, n, PAGE):
            if (pa + off) in self.dead:
                raise OSError(1450, "no system resources")
        buf = bytearray(n)
        if 0 <= self.at < n - 8:
            buf[self.at:self.at + 8] = PAT
        return bytes(buf)

    def is_ram(self, pa):
        return True


def run(ranges, dead, hopmax=dl.HOP_MAX, cap=1000, at=0x40):
    dl.SCAN_STOPPED = False
    g = Fake(dead, at=at)
    return g, pp.pid_scan(g, ranges, PID, cap=cap, hopmax=hopmax)


# --- hop over a hole -------------------------------------------------------
# 0x3000000 is clean in badpa (grid ends at 0x2000000), so this exercises the
# real fault path, not the pin path.  Span > SCAN_CHUNK so a chunk survives
# behind the dead page: the walk must reach it.
g, (hits, faults) = run([(0x3000000, 0x3040000)], {0x3010000})
check("hop: no abort", not dl.SCAN_STOPPED)
check("hop: one page lost", faults == 1, "faults=%d" % faults)
check("hop: hits survive past the hole", any(h >= 0x3010000 for h in hits),
      "hits=%s" % [hex(h) for h in hits])
check("hop: hop line names the page",
      "HOP page=0x3010000 lost=1/64" in open(dl.PROG, encoding="utf-8").read())

# --- budget trip -----------------------------------------------------------
dl.SCAN_STOPPED = False
g, (hits, faults) = run([(0x3000000, 0x3200000)],
                        set(range(0x3000000, 0x3200000, PAGE)), hopmax=4, cap=10)
prog = open(dl.PROG, encoding="utf-8").read()
check("budget: scan stopped", dl.SCAN_STOPPED)
check("budget: exactly hopmax pages lost", faults == 4, "faults=%d" % faults)
check("budget: SCANSTOP names pa+budget",
      "SCANSTOP pa=0x3003000 hopmax=4" in prog)
check("budget: did not walk 2 MiB", len(g.reads) < 200, "reads=%d" % len(g.reads))

# --- known-bad page is never re-read --------------------------------------
# dead everywhere, so the fast-path chunk fails and only the pin path can save
# the walk; the four pinned pages must cost zero reads and zero faults.
dl.SCAN_STOPPED = False
g, (hits, faults) = run([(0x200000, 0x204000)],
                        set(range(0x200000, 0x204000, PAGE)))
prog = open(dl.PROG, encoding="utf-8").read()
check("skip: pinned pages never page-read",
      [r for r in g.reads if r[1] == PAGE] == [], "reads=%s" % g.reads)
check("skip: not counted as faults", faults == 0 and hits == [],
      "faults=%d hits=%d" % (faults, len(hits)))
check("skip: PIDSCANEND carries skip=4", "skip=4" in prog)

# --- skip and fault mix, budget survives the skip -------------------------
# one pinned page, then two good pages (a hit each), then one dead page.
dl.SCAN_STOPPED = False
g, (hits, faults) = run([(0x200000, 0x201000), (0x2000000, 0x2003000)],
                        {0x2002000}, hopmax=3)
check("mix: one skipped, one lost, no abort",
      faults == 1 and not dl.SCAN_STOPPED, "faults=%d" % faults)
check("mix: good pages behind the skip still yield", len(hits) >= 2,
      "hits=%d" % len(hits))

# --- clean run unchanged ---------------------------------------------------
g, (hits, faults) = run([(0x3000000, 0x3004000)], set())
check("clean run: one chunk, one hit, no faults",
      len(hits) == len(g.reads) == 1 and faults == 0,
      "hits=%d faults=%d" % (len(hits), faults))
check("PIDSCANEND carries skip count",
      "skip=0" in open(dl.PROG, encoding="utf-8").read())

print("\n=== resume window (p96 argv2) ===")
RANGES, NOTE = dl.usable_ranges(0x40000000, lo=0x300000)
check("resume: ranges note reports the subtraction", "bad=" in NOTE,
      "note=%s" % NOTE)
check("resume: nothing below the resume point", min(a for a, _ in RANGES) >= 0x300000)
# the grid is contiguous to 0x2000000, so the whole 0x300000 pocket is already
# blacklisted and the walk restarts at the first clean page above it
check("resume: walk restarts past the grid", RANGES[0][0] == 0x2000000,
      "first=%#x" % RANGES[0][0])
check("resume: 0x300000 itself is still blacklisted", dl.in_bad(0x300000))

print("\n%s (%d failure(s))" % ("PASS" if not FAIL else "FAIL", len(FAIL)))
sys.exit(1 if FAIL else 0)

sys.exit(1 if FAIL else 0)
