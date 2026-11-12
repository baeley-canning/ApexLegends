r"""_qk_dtb7.py -- same validation, but tables are read through gio's MAP path
(IOCTL_MAP_EX / MmMapIoSpace) instead of the copy path that returns 1450 on this
page.  Different driver code path, same physical page.
"""
import ctypes
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio                      # noqa: E402
import dumplive as dl           # noqa: E402
import qk_va as VA              # noqa: E402

OUT = os.path.join(HERE, "_qk_dtb7.txt")
BASE = 0x5F06A8080
DTB = 0x694C6F000
PEB = 0x38C000


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


def page_read(g, pa):
    """0x1000 bytes at pa via the map path, falling back to the copy path."""
    try:
        va = g.map_page_cached(pa)
        if isinstance(va, tuple):
            va = va[0]
        return ctypes.string_at(va, 0x1000)
    except OSError as e:
        say("  map %#x failed: %s - trying copy path" % (pa, e))
    return dl.retry_phys(g, pa, 0x1000, tries=10)


def walk(g, dtb, vaddr):
    """Walk with mapped page reads: returns (pa_of_page, note)."""
    t = dtb & 0xFFFFFFFFFF000
    for sh in (39, 30, 21):
        pg = page_read(g, t)
        e = struct.unpack_from("<Q", pg, ((vaddr >> sh) & 0x1FF) * 8)[0]
        if not (e & 1):
            return None, "absent lvl %d" % sh
        if (e & 0x80) and sh == 21:
            return (e & 0xFFFFFFFFFF000) + (vaddr & 0x1FFFFF), "ok2M"
        t = e & 0xFFFFFFFFFF000
    pg = page_read(g, t)
    return t + (vaddr & 0xFFF), "ok"


with open(OUT, "w") as f:
    f.write("")
dl.PROC_NAME = "r5apex"
pid = dl.find_pid()
say("pid=%s" % pid)
if not pid:
    sys.exit(2)
g = gio.Gio(chunk=0x40000)

pg = page_read(g, DTB)
say("dtb page read ok via map, first qword=%#x entry255=%#x"
    % (struct.unpack_from("<Q", pg, 0)[0], struct.unpack_from("<Q", pg, 0xFF * 8)[0]))

peb_pa, note = walk(g, DTB, PEB)
say("walk PEB -> %s (%s)" % (("%#x" % peb_pa) if peb_pa else "NULL", note))
if peb_pa:
    show = page_read(g, peb_pa & ~0xFFF)
    ib = struct.unpack_from("<Q", show, peb_pa & 0xFFF)[0] if (peb_pa & 0xFFF) <= 0xFF8 else 0
    say("PEB.ImageBase=%#x" % ib)
    if ib:
        bpa, note2 = walk(g, DTB, ib)
        say("image walk -> %s (%s)" % (("%#x" % bpa) if bpa else "NULL", note2))
        if bpa:
            ipg = page_read(g, bpa & ~0xFFF)
            mz = ipg[bpa & 0xFFF: (bpa & 0xFFF) + 2]
            say("mz=%r" % mz)
            if mz == b"MZ":
                VA.save_cache(pid, DTB, ib)
                say("CACHE WRITTEN pid=%d dtb=%#x base=%#x" % (pid, DTB, ib))
                say("VERDICT: PASS")
                sys.exit(0)
say("VERDICT: PARTIAL")
sys.exit(3)
