r"""p77_frames.py -- readability snapshot of every frame that matters, right now.

p74-p76 establish the fault class: a specific frame answers 1450 to read AND
map, at every size and offset, for minutes, while its neighbours read; the
class is not tied to the process (one old Apex DTB answers it too) and not to
page-table content.  So blindness has to be measured per frame at the moment
of use, not assumed from an older log.

Frames and why:
  ctl  0x4a3410000  pid 19912 EPROCESS page, reads every time   (control)
  dtb  0x4a6be3000  pid 19912 PML4, the walk's first step       (blocked here)
  old  0x57e88c000  Apex PML4 that answered OK 15 min ago       (lifting check)
  dead 0x6c6af0000  the dead target frame                       (the actual goal)
  cand 0x6c6a00000 0x6c0be0000 0x6c0000000  other candidate frames
A readable PML4 is decoded as far as it can be (present counts per 256-entry
half) so a hit is evidence, not just an OK.  Read-only.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio  # noqa: E402

OUT = os.path.join(HERE, "_p77_frames.txt")
PAGE = 0x1000


def log(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")
    print(s)


def main():
    if os.path.exists(OUT):
        os.remove(OUT)
    log("p77 frames")
    with gio.Gio() as g:
        for tag, pa, tries in (("ctl", 0x4A3410000, 1),
                               ("dtb", 0x4A6BE3000, 3),
                               ("old", 0x57E88C000, 3),
                               ("dead", 0x6C6AF0000, 3),
                               ("cand", 0x6C6A00000, 1),
                               ("cand", 0x6C0BE0000, 1),
                               ("cand", 0x6C0000000, 1)):
            res = "err"
            for _ in range(tries):
                try:
                    b = g.read_phys(pa, PAGE)
                    res = "OK"
                    break
                except OSError as e:
                    res = "err %d" % (e.args[0] if e.args else -1)
            if res != "OK":
                log("%s %#x ram=%s -> %s" % (tag, pa, g.is_ram(pa), res))
                continue
            lo = sum(1 for i in range(0, 0x800, 8)
                     if struct.unpack_from("<Q", b, i)[0] & 1)
            hi = sum(1 for i in range(0x800, PAGE, 8)
                     if struct.unpack_from("<Q", b, i)[0] & 1)
            log("%s %#x ram=%s -> OK present lo=%d hi=%d first=%016x"
                % (tag, pa, g.is_ram(pa), lo, hi, struct.unpack_from("<Q", b, 0)[0]))
            log("  %s" % " ".join("%016x" % struct.unpack_from("<Q", b, i)[0]
                                  for i in range(0, 64, 8)))
    log("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
