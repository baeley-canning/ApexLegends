r"""h395 -- gdrv3 MapK versus failing physical copy on the SAME known live page.
No new driver, writes, service change or guessed MMIO.  Only a control page
already validated through the current EPROCESS-backed notes and real RAM map.
Read-only mapping side effect is reversed with UNMAP before every return.
"""
import ctypes as C
import os
import struct
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio
import dumplive as dl
import qk_va

OUT = os.path.join(ROOT, "temp", "h395_gdrv_map.txt")
def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")

k = C.WinDLL("kernel32", use_last_error=True)
k.VirtualAlloc.argtypes = [C.c_void_p, C.c_size_t, C.c_ulong, C.c_ulong]
k.VirtualAlloc.restype = C.c_void_p
k.VirtualLock.argtypes = [C.c_void_p, C.c_size_t]

open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
g = gio.Gio(chunk=0x1000)
ranges, note = dl.usable_ranges(g.ram_top, None, None)
g.is_ram = qk_va.Ram(ranges).page_ok
dst = k.VirtualAlloc(None, 0x1000, 0x1000 | 0x2000, 0x04)
k.VirtualLock(dst, 0x1000)
say("gdrv3 MapK positive control, ranges=%s dst=%#x" % (note, dst))
for pa in (0x1F9B2B000, 0x2D87FB000, 0x5732E3000, 0x33BCB0000):
    if not g.is_ram(pa):
        say("guard refuse=%#x" % pa)
        continue
    va, kva, got = None, None, None
    try:
        req = struct.pack("<QIIQ", pa, 0x1000, 0, dst)
        ok, err, out, got = g._ioctl(gio.IOCTL_MAP_K, req, 0x40)
        say("MAP_K pa=%#x ok=%d err=%d got=%d out=%s" %
            (pa, ok, err, got, out.hex()))
        va = struct.unpack_from("<Q", out)[0] if got >= 8 else None
        kva = va
        if va and va < 0x800000000000:
            sample = C.string_at(va, 16)
            say("MAPPED_READ=%s" % sample.hex())
            C.windll.kernel32.VirtualFree(C.c_void_p(va), 0, 0x8000)
        # The full two-qword result is returned by the same driver contract;
        # never print as 'VA' if the dispatch only copied into the scratch page.
        sample = C.string_at(dst, 16)
        say("DEST_READBACK=%s" % sample.hex())
    except Exception as e:
        say("exception %r" % (e,))
    if kva:
        try:
            g.unmap(kva, 0x1000)
            say("unmap ok")
        except OSError:
            pass
g.close()
say("closed gdrv3")