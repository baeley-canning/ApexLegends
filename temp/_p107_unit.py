"""Offline check of the p104 PINNED_FAULT handling and the p107 hop stride.

Exercises dumplive.in_bad / load_bad against the real badpa file and pid_scan
against a fake Gio, so the hop, the skip, the SCANSTOP verdict and the strided
edge walk are proven before anything touches the host driver.

p107 tags: stride counts *pages*, so it must survive the 16-page fast path, must
collapse to 1 the moment a page reads again, and must not change one byte of the
stride-1 output the harness already greps for.
"""
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))
os.environ["DUMP_PROG"] = "_p107_prog.txt"
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


def prog_since(pos):
    """Prog text written since `pos`, so a check cannot pass on an older run."""
    with open(dl.PROG, encoding="utf-8") as fh:
        fh.seek(pos)
        return fh.read()


def prog_len():
    try:
        return os.path.getsize(dl.PROG)
    except OSError:
        return 0


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


def run(ranges, dead, hopmax=dl.HOP_MAX, cap=1000, at=0x40, stride=None):
    dl.SCAN_STOPPED = False
    g = Fake(dead, at=at)
    return g, pp.pid_scan(g, ranges, PID, cap=cap, hopmax=hopmax, stride=stride)


# --- hop over a hole -------------------------------------------------------
# 0x3000000 is clean in badpa (grid ends at 0x2000000), so this exercises the
# real fault path, not the pin path.  Span > SCAN_CHUNK so a chunk survives
# behind the dead page: the walk must reach it.
pos = prog_len()
g, (hits, faults) = run([(0x3000000, 0x3040000)], {0x3010000})
check("hop: no abort", not dl.SCAN_STOPPED)
check("hop: one page lost", faults == 1, "faults=%d" % faults)
check("hop: hits survive past the hole", any(h >= 0x3010000 for h in hits),
      "hits=%s" % [hex(h) for h in hits])
check("hop: hop line names the page",
      "HOP page=0x3010000 lost=1/64" in prog_since(pos))
check("hop: stride-1 line has no suffix",
      "stride=" not in prog_since(pos).split("HOP", 1)[1].split("\n")[0])
check("hop: first good page recorded", dl.FIRST_GOOD == 0x3011000,
      "first=%#x" % dl.FIRST_GOOD)

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
pos = prog_len()
g, (hits, faults) = run([(0x200000, 0x204000)],
                        set(range(0x200000, 0x204000, PAGE)))
check("skip: pinned pages never page-read",
      [r for r in g.reads if r[1] == PAGE] == [], "reads=%s" % g.reads)
check("skip: not counted as faults", faults == 0 and hits == [],
      "faults=%d hits=%d" % (faults, len(hits)))
check("skip: PIDSCANEND carries skip=4", "skip=4" in prog_since(pos))

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
pos = prog_len()
g, (hits, faults) = run([(0x3000000, 0x3004000)], set())
check("clean run: one chunk, one hit, no faults",
      len(hits) == len(g.reads) == 1 and faults == 0,
      "hits=%d faults=%d" % (hits and len(hits) or 0, faults))
check("PIDSCANEND carries skip count", "skip=0" in prog_since(pos))
check("clean run: first good page is the start", dl.FIRST_GOOD == 0x3000000,
      "first=%#x" % dl.FIRST_GOOD)


print("\n=== hop stride (p107) ===")
# A stride must be in *pages* and must out-reach the 16-page fast path, or the
# chunk read fails 16 times for every page the walk actually advances.  Here one
# dead page at the start of a 32-page range is crossed in exactly one hop, the
# next chunk reads clean and the walk has to be dense again behind it.
pos = prog_len()
g, (hits, faults) = run([(0x3000000, 0x3020000)], {0x3000000, 0x3011000},
                        hopmax=64, stride=16)
prog = prog_since(pos)
hops = [ln for ln in prog.splitlines() if " HOP " in ln]
# one hop inside the pocket, one behind the edge: 2 faults, nothing else
check("stride: pocket crossed in a single hop", faults == 2, "faults=%d" % faults)
check("stride: hop line declares the stride", hops and "stride=16" in hops[0],
      "hop=%s" % (hops[0] if hops else "-"))
check("stride: edge is the first page that read",
      dl.FIRST_GOOD == 0x3012000,   # second fault sits 1 page in, so recovery +1
      "first=%#x" % dl.FIRST_GOOD)
check("stride: no abort", not dl.SCAN_STOPPED)
check("stride: collapses to one page behind the edge",
      len(hops) == 2 and hops[1].endswith("HOP page=0x3011000 lost=1/64"),
      "hops=%s" % hops)
check("stride: good RAM behind the edge is swept",
      any(0x3010000 <= h < 0x3011000 for h in hits) and
      any(h >= 0x3012000 for h in hits),
      "hits=%s" % [hex(h) for h in hits])
check("stride: EDGE fields survive on the module",
      dl.HOP_LAST == 0x3011000, "lastbad=%#x" % dl.HOP_LAST)

# budget counts hops, not bytes: 4 hops of 16 pages must stop 64 pages in
dl.SCAN_STOPPED = False
pos = prog_len()
g, (hits, faults) = run([(0x3000000, 0x3200000)],
                        set(range(0x3000000, 0x3200000, PAGE)),
                        hopmax=4, cap=10, stride=16)
prog = prog_since(pos)
check("stride: budget still counts hops", faults == 4 and dl.SCAN_STOPPED,
      "faults=%d" % faults)
check("stride: SCANSTOP pa is 4 strides in",
      "SCANSTOP pa=0x3030000 " in prog, "prog=%r" % prog[-90:])
check("stride: PIDSCANEND carries first=0", "first=0x0" in prog)

# dl.HOP_STRIDE is the default when no kwarg is passed (that is how p96 calls it)
dl.HOP_STRIDE = 8
pos = prog_len()
g, (hits, faults) = run([(0x3000000, 0x3020000)], {0x3000000}, hopmax=64)
check("stride: env value is used when stride is None",
      "stride=8" in prog_since(pos), "faults=%d" % faults)
dl.HOP_STRIDE = 1
pos = prog_len()
g, (hits, faults) = run([(0x3000000, 0x3010000)], {0x3000000}, hopmax=64)
check("stride: back to 1 means no suffix again",
      "HOP page=0x3000000 lost=1/64\n" in prog_since(pos))

print("\n=== resume window (p96 argv2) ===")
RANGES, NOTE = dl.usable_ranges(0x40000000, lo=0x300000)
check("resume: ranges note reports the subtraction", "bad=" in NOTE,
      "note=%s" % NOTE)
check("resume: nothing below the resume point",
      min(a for a, _ in RANGES) >= 0x300000)
# the grid is contiguous to 0x2000000, so the whole 0x300000 pocket is already
# blacklisted and the walk restarts at the first clean page above it
check("resume: walk restarts past the grid", RANGES[0][0] == 0x2000000,
      "first=%#x" % RANGES[0][0])
check("resume: 0x300000 itself is still blacklisted", dl.in_bad(0x300000))

print("\n%s (%d failure(s))" % ("PASS" if not FAIL else "FAIL", len(FAIL)))
sys.exit(1 if FAIL else 0)

