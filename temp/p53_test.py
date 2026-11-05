"""offline test for p53_padump: fake transport, no device, no game."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))
import gio              # noqa: E402
import p53_padump as P  # noqa: E402

OUT = os.path.join(HERE, "p53_padump_test.txt")
NAME = b"A Succulent Chinese Meal\x00"


def page(hit_off, fill):
    b = bytearray([fill]) * 0x1000        # bytearray(0) would be empty, not zeros
    if hit_off is not None:
        b[hit_off:hit_off + len(NAME)] = NAME
    return bytes(b)


PAGES = {
    0x100000: page(0x140, 0x00),
    0x101000: None,                       # fault on purpose
    0x102000: page(0x3c0, 0x41),
}


class FakeG(object):
    ram_top = 0x800000000

    def is_ram(self, pa):
        return 0x1000 <= pa < self.ram_top

    def read_phys_checked(self, pa, n):
        d = PAGES.get(pa)
        if d is None:
            raise OSError(1450, "phys read %#x failed" % pa)
        return d

    def close(self):
        pass


P.gio.Gio = lambda: FakeG()
rc = P.main(["--pa=0x100000", "--pages=3", "--hit=0x100140",
             "--hit=0x1023c0", "--label=t", "--out=" + OUT])
LOG = os.path.join(HERE, "p53_test_out.txt")
fail = []


def check(cond, msg):
    if not cond:
        fail.append(msg)


txt = open(OUT, encoding="utf-8").read()
check(rc == 0, "rc=%r (fault page must not be fatal)" % rc)
check(txt.count("PAGE  ") == 2, "readable pages not both dumped")
check("FAULT pa=0x101000" in txt, "fault page not reported")
check("<41" in txt and "  *" in txt, "hit byte not marked")
check("hits=2/2" in txt, "hit accounting wrong")
check(txt.count("VERDICT: PADUMP") == 1, "missing/dup verdict")
row = [l for l in txt.splitlines() if "A Succ" in l]
check(bool(row) and row[0].startswith("    000140 "), "name row not at 0x140: %r" % row[:1])
# column width must stay fixed so offsets are greppable
check(all(len(l[11:].split(" |")[0]) == 48 for l in txt.splitlines() if l.startswith("    ")),
      "hex column width varies")
with open(LOG, "w", encoding="utf-8") as f:
    f.write(("FAIL: " + "; ".join(fail) + "\n") if fail else "P53_PADUMP_OK rc=0 pages=2 fault=1 hits=2/2\n")
if fail:
    print("FAIL: " + "; ".join(fail))
    sys.exit(1)
print("P53_PADUMP_OK rc=%d pages=2 fault=1 hits=2/2" % rc)
