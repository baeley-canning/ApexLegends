r"""h398 minimal current EPROCESS discovery, not another memory API.
Search exactly `r5apex_dx12.exe` and validate live pid at EPROCESS+1D0.
Type at +0 and DirectoryTableBase at +0x28 are from the CURRENT kernel PDB.
This deliberately does NOT reuse `Proc` assumptions blindly.
"""
import os, struct, sys, time
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,"ext"))
import gio, dumplive as dl, qk_va, qk_gdrv_mapread
OUT=os.path.join(ROOT,"temp","h398_objects_only.txt")
def say(s):
    print(s,flush=True)
    with open(OUT,"a",encoding="ascii") as f:f.write(s+"\n")
open(OUT,"w").close()
pid=qk_bridge.find_pid()[0] if 'qk_bridge' in globals() else 14624
g=gio.Gio(chunk=0x1000)
mr=qk_gdrv_mapread.install(g)
g.read_phys=mr.read
say("h398 object-only current pid=%d ranges=%s"%(pid,mr.note))
dl.PROG=os.path.join(ROOT,"temp","h398_prog.txt")
dl.NAME=b"r5apex_dx12.ex\0"
hits, skipped, chunks, rescued = dl.name_hits(g, mr.ranges)
say("hits=%d skipped=%d rescued=%d chunks=%d"%(len(hits),skipped,len(rescued),chunks))
for hit in hits:
    try:
        obj=hit-0x338
        p=mr.read(obj,0x600)
    except OSError as e:
        say("hit=%#x obj read fail %s"%(hit,e));continue
    typ=p[0] if len(p) else -1
    dtb=struct.unpack_from("<Q",p,0x28)[0]
    lpid=struct.unpack_from("<I",p,0x1D0)[0]
    name=p[0x338:0x338+15]
    pl=struct.unpack_from("<Q",p,0x1D8)[0]
    bl=struct.unpack_from("<Q",p,0x1E0)[0]
    say("OBJ=%#x type=%d PID=%d NAME=%r DTB=%#x LINKS=%#x/%#x"%(obj,typ,lpid,name,dtb,pl,bl))
    if typ==3 and lpid==pid and name==dl.NAME:
        say("CONFIRMED_EPROCESS obj=%#x dtb=%#x"%(obj,dtb))
g.close()
say("RESULT: raw current object candidates recorded")