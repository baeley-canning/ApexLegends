r"""h405 -- only exact EPROCESS names; no Proc-shape extrapolation.
Start with the same completed canonical f135 raw record shape team/code.
Produce score diagnostics instead of discarding actually valid proc tags.
Still read-only, never a new driver or write side effects.
"""
import ctypes as C,os,struct,sys,time
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,"ext"))
import gio,dumplive as dl,qk_va,qk_gdrv_mapread,qk_bridge
OUT=os.path.join(ROOT,"temp","h405_proc_exact.txt")
def say(s):
    print(s,flush=True)
    with open(OUT,"a",encoding="ascii") as f:f.write(s+"\n")
open(OUT,"w").close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
pid=qk_bridge.find_pid()[0]
g=gio.Gio(chunk=0x1000)
mr=qk_gdrv_mapread.install(g);g.read_phys=mr.read
say("CURRENT_PID=%d PEB=%#x"%(pid,qk_va._peb_va(pid)))
dl.NAME=b"r5apex_dx12.ex\0"
hits=[]
for lo,hi in mr.ranges:
    at=lo
    while at+0x1000<=hi:
        try:
            b=mr.read(at,0x1000)
        except OSError:
            at+=0x1000;continue
        for add in (0x338,0x3A8):
            off=b.find(dl.NAME)
            if off>=0 and add==0x338:
                say('namehit raw_PA=%#x at_page_offset=%#x'%(at,off))
                for delta in (0x10,0xC,0x8,0x0):
                    pass
        at+=0x1000
    break
g.close()