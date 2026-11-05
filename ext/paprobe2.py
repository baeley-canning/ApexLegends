"""paprobe2.py -- is 0x7ec76d000 an isolated hole, and is the map path usable?

The 1450 is raised by gdrv3's own mapping for that one page while its
neighbours and far pages read fine.  This sweeps +/-0x40 pages around the frame
to size the hole and tries map_phys (a different ioctl path) on the frame
itself.  Read-only.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

OUT = os.path.join(os.path.dirname(HERE), "_ritual", "p44b_pa.txt")
PA = 0x7EC76D000
LOG = []


def log(s):
    LOG.append(s)
    print(s)


g = gio.Gio(chunk=0x10000)
bad = []
for i in range(-0x40, 0x41):
    p = PA + i * 0x1000
    try:
        g.read_phys(p, 0x1000)
    except OSError:
        bad.append(i)
log("sweep pages=%d bad=%d offs=%s" % (0x81, len(bad),
                                       ",".join("%+d" % b for b in bad[:24])))
for tag, size in (("copy 0x2000", 0x2000), ("copy unaligned", 0x1000)):
    pa = PA if size == 0x2000 else PA + 0x800
    try:
        g.read_phys(pa, size)
        log("%-15s %#x ok" % (tag, pa))
    except OSError as e:
        log("%-15s %#x ERR %s" % (tag, pa, e))
try:
    va, got = g.map_phys(PA, 0x1000)
    log("map_phys ok va=%#x got=%#x head=%s"
        % (va, got, __import__("ctypes").string_at(va, 16).hex()))
    g.unmap(va, got)
except OSError as e:
    log("map_phys ERR %s" % e)
g.close()
open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
print("VERDICT: PAPROBE2_DONE")
