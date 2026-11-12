r"""_p135b_read.py -- what read size still works after the 1450 storm?

p132b: exactly one successful ioctl per handle, then errno 1450 (ERROR_NO_SYSTEM_RESOURCES =
system PTEs / paged pool), for every size 2..16 MB, on a freshly restarted driver.  One 1 MB read
works, the second fails.  This decides between two very different cures:
  * small sizes keep working -> only big mappings are starved: census at that size.
  * nothing keeps working       -> the pool is gone: reboot (R2, ask the user).

20 reads per size from one handle at distinct PAs, successes counted.  Read-only.
Writes temp\_p135b_out.txt.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import gio
import dumplive as dl

OUT = os.path.join(HERE, "_p135b_out.txt")
BASE = 0x140000000


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== p135b read-size survival %s base=%#x ===" % (BASE, BASE))
    for size in (0x1000, 0x10000, 0x100000, 0x400000, 0x1000000):
        try:
            g = gio.Gio(chunk=size)
        except OSError as e:
            say("%#08x: open failed %s" % (size, e))
            continue
        okc, errs = 0, {}
        for i in range(20):
            try:
                g.read_phys(BASE + i * 0x2000000, size)
                okc += 1
            except OSError as e:
                errs[e.errno] = errs.get(e.errno, 0) + 1
        g.close()
        say("%#08x: ok=%d/20 errs=%s" % (size, okc, errs or "-"))
    say("RESULT: done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
