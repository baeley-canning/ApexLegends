r"""h394 -- use the EXISTING ApexDrv v16 read-only control to see whether its
pointer/DTB plus physical-copy primitives can establish image translation.

No driver/service mutations and none of the write/injection commands. Merely
BASE and DTB queries plus PHYS reads, same mechanism as FACTS proof qk_va_drv1.
Output: temp/_h394_v16.txt. Separate direct virtual read test in qk_probe will
be gated by this physical transport read-back first, never just assumed safe.
"""
import os
import struct
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio
import dumplive as dl
import qk_va as va

PID = 14008
OUT = os.path.join(ROOT, "temp", "_h394_v16.txt")


def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")


open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
say("=== h394 alternative read bridge %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
say("PID=%d driver_path=C:\\apexdrv.sys; no load/start/stop/configure" % PID)
g = gio.Gio(chunk=0x1000)
ranges, note = dl.usable_ranges(g.ram_top, None, None)
g.is_ram = va.Ram(ranges).page_ok
try:
    m = va.map_from_driver(PID)
    say("MAP=%s" % m)
    if not m:
        say("VERDICT: BLOCKED - installed Alternate Bridge service not read-ready")
        sys.exit(3)
    try:
        print("driver physical read control", va.drv_phys(0x1000, 16).hex(), flush=True)
        with open(OUT, "a") as f:
            f.write("driver_phys_control=" + va.drv_phys(0x1000, 16).hex() + "\n")
    except OSError as e:
        say("driver_phys_control_error=%s" % e)
    if m["base"]:
        old = g.read_phys
        g.read_phys = va.drv_phys
        reader = va.Reader(g, m["dtb"])
        peb = va._peb_va(PID)
        raw = reader.read(peb + 0x10, 8)
        say("PEB=%#x IMAGE_BASE=%r" % (peb, raw))
        if raw:
            base = struct.unpack("<Q", raw)[0]
            page = reader.read(base, 0x1000)
            meta = dl.validate_pe(page) if page else None
            say("BASE=%#x image_pa=%s meta=%s" % (base, reader.page_pa(base), meta))
            if meta:
                say("RESULT: DTB=%#x image_va=%#x translated=True" % (m["dtb"], base))
                say("VERDICT: PASS - alternative zero-attach physical read")
                sys.exit(0)
    say("VERDICT: BLOCKED_READ - no validated PE")
except Exception:
    import traceback
    say(traceback.format_exc())
    say("VERDICT: FAIL - alternative read failed or blocked")
finally:
    g.close()