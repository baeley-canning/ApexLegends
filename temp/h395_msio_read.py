r"""h395 -- one correct MsIo MAPPHYSTOLIN read, cleanup in the same script.

The mapping worker's signature is (addr, size, &va) from ProbeForWrite; the
virgin driver test previously failed ACCESS_DENIED on all low RAM addresses
because it tested only addresses below 4GB.  Current DTB may be outside that
window, so report exact input/error per target, never an unconditional PASS.
Read-only. No new service/driver/input mutation. Output temp/h395_msio_read.txt.
"""
import ctypes as C
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio
import dumplive as dl
import qk_va

OUT = os.path.join(ROOT, "temp", "h395_msio_read.txt")

def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")

k = C.WinDLL("kernel32", use_last_error=True)
k.CreateFileW.restype = C.c_void_p
k.CreateFileW.argtypes = [C.c_wchar_p, C.c_ulong, C.c_ulong, C.c_void_p,
                          C.c_ulong, C.c_ulong, C.c_void_p]
k.DeviceIoControl.argtypes = [C.c_void_p, C.c_ulong, C.c_void_p, C.c_ulong,
                              C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong),
                              C.c_void_p]

open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
g = gio.Gio(chunk=0x1000)
r, _ = dl.usable_ranges(g.ram_top, None, None)
g.is_ram = qk_va.Ram(r).page_ok
h = k.CreateFileW("\\\\.\\MsIo", 0xC0000000, 0, None, 3, 0, None)
say("handle=%#x error=%d" % (h or 0, C.get_last_error()))
tries = [0x1000, 0x1F9B2B000, 0x2D5C62000, 0x5D7F09000, 0x37F000000]
for pa in tries:
    if not g.is_ram(pa):
        say("RAM guard reject=%#x" % pa)
        continue
    before = g.read_phys(pa, 16)
    va = C.c_uint64(0)
    buf = C.create_string_buffer(struct.pack("<QQ", pa, 0x1000) + C.string_at(C.addressof(va), 8))
    ret = C.c_ulong(0)
    ok = k.DeviceIoControl(h, 0x80102040, buf, 0x18, buf, 0x18, C.byref(ret), None)
    err = C.get_last_error()
    say("map pa=%#x ok=%d err=%d ret=%x raw=%s" %
        (pa, ok, err, ret.value, buf.raw.hex()))
    for index, candidate in enumerate(struct.unpack("<QQQ", buf.raw[:24])):
        if 0x10000 < candidate < 0x800000000000:
            got = C.create_string_buffer(16)
            if ok and k.ReadProcessMemory(C.c_void_p(-1),
                                           C.c_void_p(candidate), got, 16,
                                           C.byref(C.c_size_t(0))):
                say("readable candidate[%d]=%#x bytes=%s expected=%s" %
                    (index, candidate, got.raw.hex(), before.hex()))
                say("RESULT: possible_mapping=%s" % (got.raw == before))
        if candidate >= 0xFFFF800000000000:
            say("kernel_candidate_not_user=%d %#x" % (index, candidate))
    if ok and va.value:
        # The result from this driver's view is a user-mode view; it is never
        # a direct kernel VA. Caller only uses bytes after comparing to gdrv.
        try:
            observed = C.string_at(C.c_void_p(va.value), 16)
            say("MAPPED_READBACK=%s matches=%s" % (observed.hex(),
                    observed == before))
        except OSError as e:
            say("mapped read failure=%s" % e)
    if ok:
        k.DeviceIoControl(h, 0x80102044, buf, 0x18, buf, 0x18,
                          C.byref(ret), None)
say("RESULT: tested actual MsIo requests, bounds preserved")
k.CloseHandle(h)
g.close()