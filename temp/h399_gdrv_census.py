r"""h399 -- guaranteed bounded object census with no guessed kernel offsets.
Use CURRENT kernel EPROCESS name, UniqueProcessId, and DTB offsets.  Always
MapK on every page. Any candidate must be located by pool tag `Proc`, not only
the image-name content. If none, use cached rmr data only as evidence.
"""
import os, struct, sys, time
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,"ext"))
import gio,dumplive as dl,qk_va,qk_gdrv_mapread
OUT=os.path.join(ROOT,"temp","h399_gdrv_census.txt")
def say(s):
    print(s,flush=True)
    with open(OUT,"a",encoding="ascii") as f:f.write(s+"\n")
open(OUT,"w").close()
pid=14624
g=gio.Gio(chunk=0x1000)
mr=qk_gdrv_mapread.install(g)
g.read_phys=mr.read
say("h399 current game pid=%d"%pid)
import importlib.util
spec=importlib.util.spec_from_file_location("h142",os.path.join(ROOT,"temp","_p142.py"))
h=importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
h.OUT=os.path.join(ROOT,"temp","h399_proc.txt")
try:os.remove(h.OUT)
except OSError:pass
h._f=open(h.OUT,"w",encoding="ascii")
try:
    dtb,seeds=h.find_dtb(g,pid,budget=120.0,seeds=[],proctag=True)
    say("find_dtb=%r"%dtb)
except Exception:
    import traceback;say(traceback.format_exc());dtb=None
if dtb:
    rd=qk_va.Reader(g,dtb)
    raw=rd.read(qk_va._peb_va(pid)+0x10,8)
    if raw:
        base=struct.unpack("<Q",raw)[0]
        meta=dl.validate_pe(rd.read(base,0x1000))
        say("RESULT: dtb=%#x base=%#x PE=%s"%(dtb,base,meta))
        say("VERDICT: %s"%("PASS" if meta else "BLOCKED"))
        qk_va.save_cache(pid,dtb,base)
g.close()