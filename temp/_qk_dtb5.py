r"""_qk_dtb5.py -- identify the found object + test the DTB value. No walks.
Dumps base+0x0..0x150 and base+0x300..0x470, scans 0..0x1400 for the pid (32-bit
compare too: a high-garbage dword would miss a strict 64-bit match), and reports
whether the dtb candidate reads at all.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio                      # noqa: E402
import dumplive as dl           # noqa: E402

OUT = os.path.join(HERE, "_qk_dtb5.txt")
BASE = 0x5F06A8080
DTB = 0x694C6F000


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


def rp(g, pa, n):
    return dl.retry_phys(g, pa, n, tries=4)


with open(OUT, "w") as f:
    f.write("")
dl.PROC_NAME = "r5apex"
pid = dl.find_pid()
say("pid=%s" % pid)
g = gio.Gio(chunk=0x40000)

say("== pid scan 0..0x1400 (64-bit AND low-32 match) ==")
for off in range(0, 0x1400, 4):
    v = struct.unpack("<Q", rp(g, BASE + off, 8))[0]
    if v == pid:
        say("  64-bit pid@+%#x = %d" % (off, pid))
    elif (v & 0xFFFFFFFF) == pid:
        say("  low32  pid@+%#x = %#x (high %#x)" % (off, v & 0xFFFFFFFF, v >> 32))

say("== dump base+0x000..0x150 ==")
b = rp(g, BASE, 0x150)
for i in range(0, 0x150, 16):
    say("  %#05x  %s" % (i, b[i:i + 16].hex(" ")))
say("== dump base+0x300..0x470 ==")
b = rp(g, BASE + 0x300, 0x170)
for i in range(0, 0x170, 16):
    say("  %#05x  %s" % (0x300 + i, b[i:i + 16].hex(" ")))

say("== dtb candidate %#x ==" % DTB)
try:
    d = rp(g, DTB, 0x40)
    say("  reads ok: %s" % d[:32].hex(" "))
    say("  entry0=%#x entry255=%#x"
        % (struct.unpack_from("<Q", d, 0)[0], struct.unpack("<Q", rp(g, DTB + 0xFF * 8, 8))[0]))
except OSError as e:
    say("  READ FAILS: %s" % e)
say("done")
