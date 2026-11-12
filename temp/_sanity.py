"""Is a 1450 frame sticky or transient? 30 bursts on two bad frames."""
import sys
sys.path.insert(0, "..\\ext")
import gio

g = gio.Gio(chunk=0x1000)
for pa in (0x10000000, 0x200000000):
    ok = 0
    for k in range(30):
        try:
            g.read_phys(pa, 0x1000)
            ok += 1
        except OSError:
            pass
    print("%#x ok=%d/30" % (pa, ok))
