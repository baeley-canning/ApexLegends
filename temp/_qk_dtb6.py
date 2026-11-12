r"""_qk_dtb6.py -- final: validate EPROCESS base/dtb with a HARD retry (1450 is the
known transient; h320 measured it persisting >150 ms under load) and write the cache.
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

OUT = os.path.join(HERE, "_qk_dtb6.txt")
BASE = 0x5F06A8080
DTB = 0x694C6F000
PEB = 0x38C000


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


def rp(g, pa, n, tries=20):
    return dl.retry_phys(g, pa, n, tries=tries)


def walk_page(g, fr, va):
    t = fr & 0xFFFFFFFFFF000
    for sh in (39, 30, 21):
        b = rp(g, t + ((va >> sh) & 0x1FF) * 8, 8, tries=12)
        e = struct.unpack("<Q", b)[0]
        if not (e & 1):
            return None, "absent lvl %d" % sh
        if (e & 0x80) and sh == 21:
            return (e & 0xFFFFFFFFFF000) + (va & 0x1FFFFF), "ok2M"
        t = e & 0xFFFFFFFFFF000
    return t + (va & 0xFFF), "ok"


with open(OUT, "w") as f:
    f.write("")
dl.RETRY_MS = 150                         # the 1450 transient needs room to clear
dl.PROC_NAME = "r5apex"
pid = dl.find_pid()
say("pid=%s" % pid)
if not pid:
    sys.exit(2)
g = gio.Gio(chunk=0x40000)

n = 0
while n < 10:
    try:
        d = rp(g, DTB, 0x1000)
        say("dtb page read ok after %d attempt-group(s), %d bytes" % (n, len(d)))
        break
    except OSError as e:
        n += 1
        say("  attempt %d: %s" % (n, e))
else:
    say("dtb page unreadable - VERDICT: PARTIAL")
    sys.exit(3)

peb_pa, note = walk_page(g, DTB, PEB)
say("walk PEB -> %s (%s)" % (("%#x" % peb_pa) if peb_pa else "NULL", note))
if peb_pa:
    ib = struct.unpack("<Q", rp(g, peb_pa + 0x10, 8))[0]
    say("PEB.ImageBase=%#x" % ib)
    bpa, note2 = walk_page(g, DTB, ib)
    mz = rp(g, bpa, 2) if bpa else None
    say("image pa=%s mz=%r (%s)" % (("%#x" % bpa) if bpa else "none", mz, note2))
    if mz == b"MZ":
        VA.save_cache(pid, DTB, ib)
        say("CACHE WRITTEN pid=%d dtb=%#x base=%#x" % (pid, DTB, ib))
        say("VERDICT: PASS")
        sys.exit(0)
say("VERDICT: PARTIAL")
sys.exit(3)
