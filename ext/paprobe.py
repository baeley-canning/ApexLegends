"""paprobe.py -- is the 1450 page-specific or device-wide?

p43z failed 12/12 on the accepted DTB frame while the object page itself read
fine.  This reads three pages (object, DTB, a page the p43q scan had hit) with
retries each and prints rc per page, so "this page" and "the device" can be
told apart.  Read-only, ~10 s.
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

OUT = os.path.join(os.path.dirname(HERE), "_ritual", "p43za_pa.txt")
PAGES = [("object", 0x2481D6000), ("dtb", 0x7EC76D000),
         ("scan-hit", 0x7E26C8000), ("low-pool", 0x312862000)]
LOG = []


def log(s):
    LOG.append(s)
    print(s)


g = gio.Gio(chunk=0x10000)
log("ram_top=%#x" % g.ram_top)
for tag, pa in PAGES:
    res = []
    head = ""
    for i in range(6):
        try:
            b = g.read_phys(pa, 0x1000)
            head = b[:16].hex()
            res.append("ok")
            break
        except OSError as e:
            res.append("ERR%s" % (getattr(e, "winerror", None) or e.errno or "?"))
            time.sleep(0.3)
    log("%-9s %#x is_ram=%s tries=%s head=%s"
        % (tag, pa, g.is_ram(pa), ",".join(res), head))
g.close()
open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
print("VERDICT: PAPROBE_DONE")
