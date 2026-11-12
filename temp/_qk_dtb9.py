r"""_qk_dtb9.py -- read the dead page through \\.\PhysicalMemory (a file-handle
transport that bypasses gdrv3 entirely), validate the dtb chain, write the cache.
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

OUT = os.path.join(HERE, "_qk_dtb9.txt")
DTB = 0x694C6F000
PEB = 0x38C000
PF_PATH = r"\\.\PhysicalMemory"


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


with open(OUT, "w") as f:
    f.write("")
dl.PROC_NAME = "r5apex"
pid = dl.find_pid()
say("pid=%s" % pid)
if not pid:
    sys.exit(2)

try:
    pf = open(PF_PATH, "rb", buffering=0)
except OSError as e:
    say("open %s failed: %s" % (PF_PATH, e))
    sys.exit(4)
say("PhysicalMemory file opened")

try:
    pf.seek(DTB)
    pg = pf.read(0x1000)
except OSError as e:
    say("read via file failed: %s" % e)
    sys.exit(4)
if len(pg) != 0x1000:
    say("short read %d" % len(pg))
    sys.exit(4)
e0 = struct.unpack_from("<Q", pg, 0)[0]
e255 = struct.unpack_from("<Q", pg, 0xFF8)[0]
say("DEAD PAGE READS VIA FILE! entry0=%#x present=%d entry255=%#x" % (e0, e0 & 1, e255))
if not (e0 & 1) and not (e255 & 1):
    say("neither entry present - not a PML4? VERDICT: PARTIAL")
    sys.exit(3)


def pread(pa, n):
    pf.seek(pa)
    return pf.read(n)


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
    say("PEB.ImageBase=%#x" % ib)
    if ib and ib < 0x7FFFFFFFFFFF:
        bpa, note2 = walk(DTB, ib)
        say("image walk -> %s (%s)" % (("%#x" % bpa) if bpa else "NULL", note2))
        if bpa:
            p = pread(bpa & ~0xFFF, 0x1000)
            mz = p[bpa & 0xFFF:(bpa & 0xFFF) + 2]
            say("mz=%r" % mz)
            if mz == b"MZ":
                VA.save_cache(pid, DTB, ib)
                say("CACHE WRITTEN pid=%d dtb=%#x base=%#x" % (pid, DTB, ib))
                say("VERDICT: PASS")
                sys.exit(0)
say("VERDICT: PARTIAL")
sys.exit(3)
