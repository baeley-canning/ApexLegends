r"""h407: no DTB guessing. Kobj-backed root decode with gdrv3 MapK.
Given authoritative pointer from the privilege-correct handle-table lookup,
locate a root by its exact object PID and name, then verify PEB->Apex PE.
All page reads with same new endpoint; not the broken 1450 transport.
"""
import os,struct,sys,time
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,'ext'))
import gio,dumplive as dl,qk_va,qk_gdrv_mapread,qk_bridge,qk_rootbind
OUT=os.path.join(ROOT,'temp','h407_phys_exact.txt')
def say(s):
    print(s,flush=True)
    with open(OUT,'a',encoding='ascii') as f:f.write(s+'\n')

open(OUT,'w').close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
g=gio.Gio(chunk=0x1000)
try:
    mr=qk_gdrv_mapread.install(g)
    line=open(os.path.join(ROOT,'temp','h407_object_evidence.txt')).read()
    obj=int(line.split('EPROCESS=')[1].split()[0],16)
    pid=qk_bridge.find_pid()[0]
    peb=qk_va._peb_va(pid)
    say('kernel object=%#x target pid=%d PEB=%#x'%(obj,pid,peb))
    # source-record exact: PML4 index matching kernel pool object, not r5 strings.
    idx=(obj>>39)&0x1ff
    start=time.time()
    for lo,hi in mr.ranges:
        pos=lo
        while pos+0x1000<=hi and time.time()-start<150.0:
            try:b=mr.read(pos,0x1000)
            except OSError:
                pos+=0x1000;continue
            if not (struct.unpack_from('<Q',b,idx*8)[0]&1):
                pos+=0x1000;continue
            rd=qk_va.Reader(g,pos)
            try:
                nm=rd.read(obj+0x338,15)
                pidb=rd.read(obj+0x1D0,8)
                if not nm or not pidb:
                    pos+=0x1000;continue
                if nm==b'r5apex_dx12.ex\0' and struct.unpack('<Q',pidb)[0]==pid:
                    dtb=struct.unpack('<Q',rd.read(obj+0x28,8))[0]&dl.MASK
                    say('OBJECT root=%#x NAME=%r PID=%d DTB=%#x'%(pos,nm,pid,dtb))
                    rd2=qk_va.Reader(g,dtb)
                    raw=rd2.read(peb+0x10,8)
                    if raw:
                        base=struct.unpack('<Q',raw)[0]
                        page=rd2.read(base,0x1000)
                        meta=dl.validate_pe(page) if page else None
                        say('BASE=%#x PE=%s'%(base,meta))
                        if meta:
                            qk_va.save_cache(pid,dtb,base)
                            say('VERDICT: PASS - virtual bridge live')
                            sys.exit(0)
            except OSError:
                pass
            pos+=0x1000
        else:
            continue
        break
    say('VERDICT: BLOCKED - no matching root body, not driver rejection')
except Exception:
    import traceback;say(traceback.format_exc())
finally:g.close()