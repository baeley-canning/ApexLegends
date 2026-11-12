r"""_qk_dtb4.py -- validate the EPROCESS probe3 found and write the dtb cache.

base=0x5F06A8080, dtb=0x694C6F000, d=0x338, prio=0x2 (from _qk_dtb3.txt).  Walks the
DTB to the PEB -> ImageBase -> MZ, hunts the pid offset (learning it for next time),
and writes qk_va's dtb cache so qk_world skips discovery entirely.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio                      # noqa: E402
import dumplive as dl           # noqa: E402
import qk_va as VA              # noqa: E402

OUT = os.path.join(HERE, "_qk_dtb4.txt")
BASE = 0x5F06A8080
DTB = 0x694C6F000
PEB = 0x38C000


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


def rp(g, pa, n):
    return dl.retry_phys(g, pa, n, tries=5)


def walk_page(g, fr, va):
    t = fr & 0xFFFFFFFFFF000
    for sh in (39, 30, 21):
        b = rp(g, t + ((va >> sh) & 0x1FF) * 8, 8)
        e = struct.unpack("<Q", b)[0]
        if not (e & 1):
            return None, "absent lvl %d" % sh
        if (e & 0x80) and sh == 21:
            return (e & 0xFFFFFFFFFF000) + (va & 0x1FFFFF), "ok2M"
        t = e & 0xFFFFFFFFFF000
    return t + (va & 0xFFF), "ok"


with open(OUT, "w") as f:
    f.write("")

dl.PROC_NAME = "r5apex"
pid = dl.find_pid()
say("pid=%s" % pid)
if not pid:
    sys.exit(2)
g = gio.Gio(chunk=0x40000)

say("name@base+0x338 = %r" % g.read_phys(BASE + 0x338, 16))
hit = 0
for off in range(0x300, 0xA00, 4):
    v = struct.unpack("<Q", rp(g, BASE + off, 8))[0]
    if v == pid:
        say("pid@+%#x = %d  <-- UniqueProcessId offset for this build" % (off, pid))
        hit += 1
    if off in (0x300, 0x340, 0x380, 0x3C0, 0x400, 0x440, 0x448, 0x480, 0x4C0,
               0x500, 0x540, 0x580, 0x5A0, 0x5C0, 0x600, 0x640, 0x680, 0x700):
        say("  +%#x: %#x" % (off, v))
if not hit:
    say("pid not found in 0x300..0xA00")
say("typebyte=%#x prio=%#x" % (g.read_phys(BASE, 1)[0], g.read_phys(BASE + 0x347, 1)[0]))

peb_pa, note = walk_page(g, DTB, 0x38C000)
say("walk PEB -> %s (%s)" % (("%#x" % peb_pa) if peb_pa else "NULL", note))
if peb_pa:
    ib = struct.unpack("<Q", rp(g, peb_pa + 0x10, 8))[0]
    say("PEB.ImageBase=%#x" % ib)
    bpa, _ = walk_page(g, DTB, ib)
    mz = rp(g, bpa, 2) if bpa else None
    say("image pa=%s mz=%r" % (("%#x" % bpa) if bpa else "none", mz))
    if mz == b"MZ":
        VA.save_cache(pid, DTB, ib)
        say("CACHE WRITTEN pid=%d dtb=%#x base=%#x" % (pid, DTB, ib))
        say("VERDICT: PASS")
        sys.exit(0)
say("VERDICT: PARTIAL")
sys.exit(3)
