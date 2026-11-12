r"""_qk_dtb13.py -- final: read the dead page through apexdrv's MmCopyMemory (the
one transport that does not MmMapIoSpace), take dtb+base straight from the driver,
walk, validate, cache.  Runs inside the kdu/apexdrv cameo window.
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

OUT = os.path.join(HERE, "_qk_dtb13.txt")
PEB = 0x38C000


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


with open(OUT, "w") as f:
    f.write("")
VA.set_out(OUT)
dl.PROC_NAME = "r5apex"
pid = dl.find_pid()
say("pid=%s" % pid)
if not pid:
    sys.exit(2)

m = VA.map_from_driver(pid)
if not m:
    say("driver gave no dtb - VERDICT: PARTIAL")
    sys.exit(4)
DTB, BASE = m["dtb"], m["base"]
say("driver: dtb=%#x base=%#x" % (DTB, BASE))


def pread(pa, n):
    """gdrv3 first, apexdrv MmCopyMemory as the fallback for dead pages."""
    try:
        return dl.retry_phys(g, pa, n, tries=2)
    except OSError:
        return VA.drv_phys(pa, n)


g = gio.Gio(chunk=0x40000)
pg = pread(DTB, 0x1000)
say("dead page via apexdrv: entry0=%#x entry255=%#x"
    % (struct.unpack_from("<Q", pg, 0)[0], struct.unpack_from("<Q", pg, 0xFF8)[0]))


def walk(dtb, vaddr):
    t = dtb & 0xFFFFFFFFFF000
    for sh in (39, 30, 21):
        p = pread(t, 0x1000)
        e = struct.unpack_from("<Q", p, ((vaddr >> sh) & 0x1FF) * 8)[0]
        if not (e & 1):
            return None, "absent lvl %d" % sh
        if (e & 0x80) and sh == 21:
            return (e & 0xFFFFFFFFFF000) + (vaddr & 0x1FFFFF), "ok2M"
        t = e & 0xFFFFFFFFFF000
    return t + (vaddr & 0xFFF), "ok"


peb_pa, note = walk(DTB, PEB)
say("walk PEB -> %s (%s)" % (("%#x" % peb_pa) if peb_pa else "NULL", note))
if peb_pa:
    p = pread(peb_pa & ~0xFFF, 0x1000)
    ib = struct.unpack_from("<Q", p, peb_pa & 0xFFF)[0]
    say("PEB.ImageBase=%#x (driver said base=%#x)" % (ib, BASE))
    if ib and ib < 0x7FFFFFFFFFFF:
        bpa, note2 = walk(DTB, ib)
        if bpa:
            p = pread(bpa & ~0xFFF, 0x1000)
            mz = p[bpa & 0xFFF:(bpa & 0xFFF) + 2]
            say("walk base mz=%r" % mz)
            if mz == b"MZ":
                VA.save_cache(pid, DTB, ib)
                say("CACHE WRITTEN pid=%d dtb=%#x base=%#x" % (pid, DTB, ib))
                say("VERDICT: PASS")
                sys.exit(0)
say("VERDICT: PARTIAL")
sys.exit(3)
