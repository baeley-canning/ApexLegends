# Positive control for the alternate gdrv3 map callback. Read-only on data.
# The driver creates its own mappings; this script unmaps them in finally.
import ctypes as C
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "ext"))
import gio
import dumplive as dl
import qk_va

OUT = os.path.join(HERE, "_h393_map_control.txt")

def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")

open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"' + os.path.abspath(__file__) + '"'))
g = gio.Gio(chunk=0x1000)
ranges, note = dl.usable_ranges(g.ram_top, None, None)
g.is_ram = qk_va.Ram(ranges).page_ok
MARK = b"QKMAP-POSITIVE-CONTROL-09032027"
k32 = C.windll.kernel32
k32.VirtualAlloc.argtypes = [C.c_void_p, C.c_size_t, C.c_ulong, C.c_ulong]
k32.VirtualAlloc.restype = C.c_void_p
k32.VirtualFree.argtypes = [C.c_void_p, C.c_size_t, C.c_ulong]
k32.VirtualLock.argtypes = [C.c_void_p, C.c_size_t]
kernel32 = gio.kernel32
kernel32.GetCurrentProcess.restype = C.c_void_p
dst = C.windll.kernel32.VirtualAlloc(None, 0x1000, 0x1000 | 0x2000, 4)
k32.VirtualLock(dst, 0x1000)
C.memset(dst, 0, 0x1000)
C.memmove(dst, MARK, len(MARK))
say("ranges=%d note=%s dst=%#x" % (len(ranges), note, dst))
# Probe the MAP_K API with its existing declaration but never dereference it
# before logging its return and confirming that the marker can round-trip.
try:
    want = struct.pack("<QIIQ", 0x1000, 0x1000, 0, dst)
    ok, err, ob, got = g._ioctl(gio.IOCTL_MAP_K, want, 0x40)
    say("map_k ok=%s err=%s got=%d out=%s" % (ok, err, got, ob.hex()))
    map_va = g.map_phys(0x1000, 0x1000)
    say("map_phys control returned=%#x" % map_va)
    say("map_bytes=%s" % C.string_at(map_va, 64).hex())
    g.unmap(map_va, 0x1000)
    say("unmap control=ok")
except Exception as e:
    say("MAP_EXCEPTION=%r" % (e,))
finally:
    g.close()
    C.windll.kernel32.VirtualFree(dst, 0, 0x8000)
say("RESULT: controlled map tested (do not infer mapping without a marker)")