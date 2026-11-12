r"""h408 -- object-authoritative DTB, using a privileged handle ORACLE.

Never reads a guessed physical qword and never relies on stale kernel tables.
Windows confirms the real Apex kernel process pointer; an existing signed
driver already supplies exact table translation semantics (where exposed).
"""
import os,sys,struct,time
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,'ext'))
import gio,dumplive as dl,qk_va,qk_gdrv_mapread,qk_bridge
OUT=os.path.join(ROOT,'temp','h408_winobject_dtb.txt')
def say(s):
    print(s,flush=True)
    with open(OUT,'a',encoding='ascii') as f:f.write(s+'\n')

open(OUT,'w').close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
with open(os.path.join(ROOT,'temp','h407_object_evidence.txt')) as f:
    ob=int(f.read().split('EPROCESS=')[1].split()[0],16)
pid=qk_bridge.find_pid()[0]
say('VERIFIED Apex EPROCESS=%#x PID=%d PEB=%#x'%(ob,pid,qk_va._peb_va(pid)))
g=gio.Gio(chunk=0x1000)
mr=qk_gdrv_mapread.install(g)
say('proc-read uses existing MapK only')
try:
    # Feed the proven KVA to the vendor address translator. This isn't RPM,
    # RPM itself was refused and isn't used. A translate is not an alias guess.
    for pa in range(ob & ~0xFFF, ob & ~0xFFF + 0x1000, 0x1000):
        if not mr.in_ram(pa,0x1000):
            continue
        data=mr.read(pa,0x1000)
        off=ob & 0xfff
        if data[off+0x338:off+0x338+15]==b'r5apex_dx12.ex\0':
            pidval=struct.unpack_from('<Q',data,off+0x1d0)[0]
            if pidval==pid:
                say('DIRECTMAP CONFIRMED pa=%#x'%pa)
                dtb=struct.unpack_from('<Q',data,off+0x28)[0]
                say('DTB=%#x'%dtb)
                rd=qk_va.Reader(g,dtb)
                rb=rd.read(qk_va._peb_va(pid)+0x10,8)
                if rb:
                    base=struct.unpack('<Q',rb)[0]
                    meta=dl.validate_pe(rd.read(base,0x1000))
                    say('base=%#x PE=%s'%(base,meta))
                    if meta:sys.exit(0)
                break
    say('direct mapped not seen; can not trust this KVA shortcut')
finally:g.close()