"""d0: post-boot driver liveness probe.  Self-elevates, opens gdrv3, reports
ram_top + a control read + two high-RAM reads.  Read-only."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))
import gio
import dumplive as dl

if not dl.elevation():
    print(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
    sys.exit(0)

try:
    g = gio.Gio(chunk=0x10000)
except OSError as e:
    print("open FAILED: %s" % e)
    sys.exit(1)
print("open ok, ram_top=%#x" % g.ram_top)
for pa in (0x1000, g.ram_top // 2, g.ram_top - 0x2000):
    try:
        print("read %#x ok: %s" % (pa, g.read_phys(pa, 0x10).hex()))
    except OSError as e:
        print("read %#x FAIL: %s" % (pa, e))
g.close()
print("done")
