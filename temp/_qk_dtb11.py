r"""_qk_dtb11.py -- is 0x694c6f000 a map hole?  Print the RAM map rows around it,
page_ok(), and in_bad() for the page and its neighbours.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import dumplive as dl           # noqa: E402
import qk_va as VA              # noqa: E402

OUT = os.path.join(HERE, "_qk_dtb11.txt")
PA = 0x694C6F000


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


with open(OUT, "w") as f:
    f.write("")

good, note = dl.ram_map()
say("map note: %s rows=%d" % (note, len(good)))
say("rows intersecting %#x..%#x:" % (PA - 0x40000, PA + 0x40000))
for lo, hi in sorted(good):
    if lo < PA + 0x40000 and hi > PA - 0x40000:
        say("  %#x-%#x  (%s)" % (lo, hi, "COVERS" if lo <= PA < hi else "near"))

ranges, rnote = dl.usable_ranges(0x800000000, None, None)
ram = VA.Ram(ranges)
for k in (-2, -1, 0, 1, 2):
    pa = PA + k * 0x1000
    say("  %#x page_ok=%s in_bad=%s" % (pa, ram.page_ok(pa), dl.in_bad(pa)))
say("usable note: %s ranges=%d" % (rnote, len(ranges)))
say("done")
