r"""h396: canonical repo DTB discovery, only MapK replaces the failing call.
No new driver, no alternate IOCTL buffer guessed, no edits to global caches.
Run canonical qk_va.discover under our proven, address-guarded new primitive.
"""
import os
import struct
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio
import dumplive as dl
import qk_va
import qk_gdrv_mapread

OUT = os.path.join(ROOT, "temp", "h396_qkva_system.txt")
def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")

open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
say("=== h396 canonical qk_va with MapK %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
g = gio.Gio(chunk=0x1000)
try:
    mr = qk_gdrv_mapread.install(g)
    say("MapK installed ranges=%s" % mr.note)
    try:
        # MapK is a page copy, physical.  Reuse that existing RAM-map guarded
        # call only, never feed kernel VAs into g.read_phys directly.
        orig = g.is_ram
        m = qk_va.discover(g, 14008)
        say("MAP=%s" % m)
        if m:
            rd = qk_va.Reader(g, m["dtb"])
            peb = qk_va._peb_va(14008)
            raw = rd.read(peb + 0x10, 8)
            say("raw=%r" % raw)
            if raw:
                base = struct.unpack("<Q", raw)[0]
                p = rd.read(base, 0x1000)
                meta = dl.validate_pe(p) if p else None
                say("base=%#x PE=%s" % (base, meta))
                if meta and meta["size"] == 0xDFB8000:
                    qk_va.save_cache(14008, m["dtb"], base)
                    say("RESULT: dtb=%#x base=%#x image_pa=%s" %
                        (m["dtb"], base, rd.page_pa(base)))
                    say("VERDICT: PASS - proven existing gdrv3 MapK read bridge")
                    sys.exit(0)
        say("VERDICT: BLOCKED - canonical discovery could not bind DTB")
    except Exception:
        import traceback
        say(traceback.format_exc())
        say("VERDICT: BLOCKED - discovery exception")
finally:
    g.close()