r"""h401 -- known current Apex PEB image base -> game root. Fixed read MapK.
 Canonical repo `dl.find_mz(g, dtb)` validates a PE before a candidate can be
 called a root.  Every raw PA comes through its own complete RAM map interval.
This is incremental, bounded by map/time, not every entity qword speculatively.
"""
import ctypes as C
import os
import struct
import sys
import time

ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,"ext"))
import gio
import dumplive as dl
import qk_va
import qk_gdrv_mapread
import qk_bridge

OUT=os.path.join(ROOT,"temp","h401_pid_table.txt")
def say(s):
    print(s,flush=True)
    with open(OUT,"a",encoding="ascii") as f:f.write(s+"\n")

open(OUT,"w").close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
g=gio.Gio(chunk=0x1000)
mr=qk_gdrv_mapread.install(g)
g.read_phys=mr.read
pd=qk_bridge.find_pid()[0]
peb=qk_va._peb_va(pd)
say("pid=%d PEB=%#x MapK_enabled=%s"%(pd,peb,mr.note))
try:
    # Re-limit explicitly because qk_va.discover expands into a full-frame scan:
    # protect the windows every candidate might use, no arbitrary-line-RAM raw PAs.
    m=qk_va.discover(g,pd)
    say("bind map=%r"%m)
    if m:
        rd=qk_va.Reader(g,m["dtb"])
        raw=rd.read(peb+0x10,8)
        if raw:
            base=struct.unpack("<Q",raw)[0]
            meta=dl.validate_pe(rd.read(base,0x1000))
            say("RESULT: base=%#x PE=%s"%(base,meta))
            if meta and meta["size"]==0xDFB8000:qk_va.save_cache(pd,m["dtb"],base)
    say("VERDICT: %s"%("PASS" if m else "BLOCKED"))
except Exception:
    import traceback;say(traceback.format_exc())
finally:g.close()