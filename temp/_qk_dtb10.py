r"""_qk_dtb10.py -- two cheap transport tricks for the dead page:
1. read the containing 64 KiB chunk (the scan's own granularity - the failing span
   may only be the exact page mapping),
2. raw CreateFileW on PhysicalMemory name variants.
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

OUT = os.path.join(HERE, "_qk_dtb10.txt")
DTB = 0x694C6F000
PEB = 0x38C000


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


with open(OUT, "w") as f:
    f.write("")
dl.PROC_NAME = "r5apex"
pid = dl.find_pid()
say("pid=%s" % pid)
g = gio.Gio(chunk=0x40000)

say("== chunk reads ==")
for pa, n in ((DTB - 0xF000, 0x10000), (DTB, 0x1000), (DTB - 0x8000, 0x10000),
              (DTB - 0xF000, 0x20000)):
    try:
        b = dl.retry_phys(g, pa, n, tries=2)
        off = DTB - pa
        if 0 <= off <= len(b) - 8:
            say("  %#x+%#x ok; bytes at dtb: %s" % (pa, n, b[off:off + 8].hex()))
        else:
            say("  %#x+%#x ok (dtb outside)" % (pa, n))
    except OSError as e:
        say("  %#x+%#x FAIL %s" % (pa, n, e))

say("== CreateFileW variants ==")
k32 = ctypes.WinDLL("kernel32", use_last_error=True)
k32.CreateFileW.restype = ctypes.c_void_p
for name in (r"\\.\PhysicalMemory", r"\\?\PhysicalMemory",
             r"\Device\PhysicalMemory", r"\\.\PhysicalMemoryMgr"):
    h = k32.CreateFileW(name, 0x80000000, 3, None, 3, 0, None)
    err = ctypes.get_last_error()
    say("  %-28s handle=%s err=%d" % (name, hex(h) if h and h != -1 else "FAIL",
                                      err))
    if h and h != ctypes.c_void_p(-1).value:
        say("    -> openable!")
