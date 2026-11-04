"""c10: print the declared RAM map + usable plan.  No driver handle needed."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "ext"))
import gio  # noqa: E402
import dumplive as dl  # noqa: E402

OUT = os.path.join(HERE, "c10_ranges_out.txt")
L = []


def w(s):
    L.append(s)
    print(s)


top = gio.installed_ram_bytes()
w("ram_top=%#x" % top)
raw, note = dl.ram_map()
w("ram_map note=%s n=%d" % (note, len(raw)))
for a, b in raw:
    w("  raw %#x..%#x  %#x" % (a, b, b - a))
plan, note2 = dl.usable_ranges(top, None, None)
w("usable note=%s n=%d" % (note2, len(plan)))
for a, b in plan:
    w("  use %#x..%#x  %#x" % (a, b, b - a))
w("total_use=%#x" % sum(b - a for a, b in plan))
open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")
