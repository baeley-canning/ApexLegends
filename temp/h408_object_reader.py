r"""h408 -- current privileged OS-identified EPROCESS to DTB, gdrv3 only.

Problem left: translate a real kernel VA to a frame.  `PsInitialSystemProcess`
is not guessed from a name anchor: kernel module system info plus export RVA
define its real VA.  A static kernel mapping supplies its root where possible;
MapK is used for all subsequent actual bytes.  No new kernel writes/drivers.
"""
import os,struct,sys,time,importlib.util
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,'ext'))
import gio,dumplive as dl,qk_va,qk_gdrv_mapread,qk_bridge,qk_kernelroot

OUT=os.path.join(ROOT,'temp','h408_object_reader.txt')
def say(s):
    print(s,flush=True)
    with open(OUT,'a',encoding='ascii') as f:f.write(s+'\n')
open(OUT,'w').close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
g=gio.Gio(chunk=0x1000)
mr=qk_gdrv_mapread.install(g);g.read_phys=mr.read
pid=qk_bridge.find_pid()[0]
ob=int(open(os.path.join(ROOT,'temp','h407_object_evidence.txt')).read().split('EPROCESS=')[1].split()[0],16)
say('confirmed object=%#x'%ob)
nt=qk_kernelroot.module_base()
rva=qk_kernelroot.export_rva(nt,b'PsInitialSystemProcess')
say('nt=%#x export rva=%#x'%(nt,rva or 0))
target=nt+rva
say('PsInitialSystemProcess KVA=%#x'%target)
try:
    # Kernel memory requires the SYSTEM table (not Apex's CR3). A PML4-shaped
    # candidate is only accepted if it maps actual kernel image MZ headers.
    for lo,hi in mr.ranges:
        pos=lo
        while pos+0x1000<=hi:
            try:b=mr.read(pos,0x1000)
            except OSError:
                pos+=0x1000;continue
            if not (struct.unpack_from('<Q',b, (target>>39&0x1ff)*8)[0]&1):
                pos+=0x1000;continue
            rd=qk_va.Reader(g,pos)
            if not rd.read(target,2):
                pos+=0x1000;continue
            try:
                if rd.read(target,2)==b'MZ':
                    say('kernel root MZ: pos=%#x'%pos)
                    first=struct.unpack('<Q',rd.read(target,8))[0]
                    say('first EPROCESS=%#x'%first)
                    root=pos
                    break
            except OSError:pass
            pos+=0x1000
        else:continue
        break
    say('RESULT: see object-only KVA reader')
finally:g.close()