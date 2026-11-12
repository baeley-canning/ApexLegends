r"""_qk_dtb12.py -- hunt for a SECOND page-table root in the EPROCESS (UserDirectoryBase
or a copy) that is readable, so no driver cameo is needed.  No writes.
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

OUT = os.path.join(HERE, "_qk_dtb12.txt")
BASE = 0x5F06A8080
PEB = 0x38C000


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


def walk(g, dtb, vaddr):
    t = dtb & 0xFFFFFFFFFF000
    for sh in (39, 30, 21):
        b = dl.retry_phys(g, t, 0x1000, tries=2)
        e = struct.unpack_from("<Q", b, ((vaddr >> sh) & 0x1FF) * 8)[0]
        if not (e & 1):
            return None, "absent lvl %d" % sh
        if (e & 0x80) and sh == 21:
            return (e & 0xFFFFFFFFFF000) + (vaddr & 0x1FFFFF), "ok2M"
        t = e & 0xFFFFFFFFFF000
    return t + (vaddr & 0xFFF), "ok"


with open(OUT, "w") as f:
    f.write("")
dl.PROC_NAME = "r5apex"
pid = dl.find_pid()
say("pid=%s" % pid)
g = gio.Gio(chunk=0x40000)
ram_top = g.ram_top

obj = dl.retry_phys(g, BASE, 0x1000, tries=3)
cands = []
for off in range(0, 0x1000 - 8, 8):
    v = struct.unpack_from("<Q", obj, off)[0]
    if 0x1000 <= v < ram_top and (v & 0xFFF) == 0 and (v >> 32) == 0:
        if v not in cands:
            cands.append(v)
say("frame-aligned candidates in object: %s" % " ".join("%#x" % c for c in cands))
for c in cands[:10]:
    offs = [i * 8 for i in range(len(cands))]
    where = [("%#x" % (i * 8)) for i in range(0x1000 // 8)
             if struct.unpack_from("<Q", obj, i * 8)[0] == c]
    try:
        b = dl.retry_phys(g, c, 0x1000, tries=2)
    except OSError as e:
        say("  %#x (at %s): UNREADABLE %s" % (c, ",".join(where[:3]), e))
        continue
    e0 = struct.unpack_from("<Q", b, 0)[0]
    e255 = struct.unpack_from("<Q", b, 0xFF8)[0]
    try:
        pa, note = walk(g, c, PEB)
        peb_note = "PEB->%s (%s)" % (("%#x" % pa) if pa else "NULL", note)
    except OSError as e:
        peb_note = "walk fault %s" % e
    say("  %#x (at %s): readable e0=%#x e255=%#x %s"
        % (c, ",".join(where[:3]), e0, e255, peb_note))
say("done")
