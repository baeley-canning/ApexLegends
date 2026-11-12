r"""_qk_dtb8.py -- is the whole region dead, or just this page, and does it recover?
Probes neighboring pages, then retries the dtb page for up to ~2 min; the moment it
reads, walk + validate + cache.
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio                      # noqa: E402
import dumplive as dl           # noqa: E402
import qk_va as VA              # noqa: E402

OUT = os.path.join(HERE, "_qk_dtb8.txt")
DTB = 0x694C6F000
PEB = 0x38C000
BASE = 0x5F06A8080


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


def rp(g, pa, n, tries=2):
    return dl.retry_phys(g, pa, n, tries=tries)


with open(OUT, "w") as f:
    f.write("")
dl.PROC_NAME = "r5apex"
pid = dl.find_pid()
say("pid=%s" % pid)
g = gio.Gio(chunk=0x40000)

say("neighbor pages:")
for k in range(-8, 9):
    pa = DTB + k * 0x1000
    try:
        b = rp(g, pa, 8, tries=1)
        say("  %#x ok  first=%#x" % (pa, struct.unpack("<Q", b)[0]))
    except OSError as e:
        say("  %#x FAIL %s" % (pa, e))

say("sustained retry on %#x ..." % DTB)
t0 = time.time()
ok_page = None
while time.time() - t0 < 120:
    try:
        ok_page = rp(g, DTB, 0x1000, tries=1)
        say("read OK after %.1fs" % (time.time() - t0))
        break
    except OSError:
        time.sleep(2.0)
if ok_page is None:
    say("still failing after 120 s - VERDICT: PARTIAL")
    sys.exit(3)

say("entry0=%#x entry255=%#x" % (struct.unpack_from("<Q", ok_page, 0)[0],
                                 struct.unpack_from("<Q", ok_page, 0xFF8)[0]))


def walk(dtb, vaddr):
    t = dtb & 0xFFFFFFFFFF000
    for sh in (39, 30, 21):
        pg = rp(g, t, 0x1000, tries=6)
        e = struct.unpack_from("<Q", pg, ((vaddr >> sh) & 0x1FF) * 8)[0]
        if not (e & 1):
            return None, "absent lvl %d" % sh
        if (e & 0x80) and sh == 21:
            return (e & 0xFFFFFFFFFF000) + (vaddr & 0x1FFFFF), "ok2M"
        t = e & 0xFFFFFFFFFF000
    return t + (vaddr & 0xFFF), "ok"


peb_pa, note = walk(DTB, PEB)
say("walk PEB -> %s (%s)" % (("%#x" % peb_pa) if peb_pa else "NULL", note))
if peb_pa:
    pg = rp(g, peb_pa & ~0xFFF, 0x1000, tries=6)
    ib = struct.unpack_from("<Q", pg, peb_pa & 0xFFF)[0]
    say("PEB.ImageBase=%#x" % ib)
    if ib:
        bpa, note2 = walk(DTB, ib)
        say("image walk %s" % note2)
        if bpa:
            pg = rp(g, bpa & ~0xFFF, 0x1000, tries=6)
            mz = pg[bpa & 0xFFF:(bpa & 0xFFF) + 2]
            say("mz=%r" % mz)
            if mz == b"MZ":
                VA.save_cache(pid, DTB, ib)
                say("CACHE WRITTEN dtb=%#x base=%#x" % (DTB, ib))
                say("VERDICT: PASS")
                sys.exit(0)
say("VERDICT: PARTIAL")
sys.exit(3)
