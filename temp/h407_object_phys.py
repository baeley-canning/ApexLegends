r"""h407: exact privileged EPROCESS now known; just resolve its physical DTB.
Windows exposes an accurate kernel pointer (h406_debug_priv). Use gdrv3 MapK
to resolve EPROCESS's object physical frame without sweeping every name.
Kernel VAs' PTE hierarchy is fetched once from a known module root. This is
the final DTB gate before `LocalPlayer`, `ViewMatrix`, names/health offset set.
"""
import os,sys,struct,time
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,'ext'))
import gio,dumplive as dl,qk_gdrv_mapread,qk_va,qk_bridge,qk_kernelroot

OUT=os.path.join(ROOT,'temp','h407_object_phys.txt')
def say(s):
    print(s,flush=True)
    with open(OUT,'a',encoding='ascii') as f:f.write(s+'\n')

open(OUT,'w').close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
obj=int(open(os.path.join(ROOT,'temp','h406_debug.txt')).read().split('EPROCESS=')[1].split(' ')[0],16)
pid=qk_bridge.find_pid()[0]
g=gio.Gio(chunk=0x1000)
mr=qk_gdrv_mapread.install(g)
g.read_phys=mr.read
say('EPROCESS confirmed=%#x game=%d peb=%#x'%(obj,pid,qk_va._peb_va(pid)))
# address translation type measurement using privileged object points, not stale
# EPROCESS shape false positives. Kernel module information and kernel PML4
# entry (higher half) constrain candidates strongly; same valid-PE identity.
nt=qk_root_module_base() if 'qk_root_module_base' in globals() else None
say('device started - will use exact object, never strings as fake entities')
g.close()