r"""h409: read from privileged confirmed EPROCESS address, no guessing.

Kernel's static equivalent was corrupted in old md files. Use fresh OS module
base identity + exact export so map is satisfied before following object list.
Object at +0x338 name and +0x1D0 pid from ACTUAL kernel's PsInitialSysproc.
"""
import ctypes as C,os,struct,sys,time
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,'ext'))
import gio,dumplive as dl,qk_va,qk_gdrv_mapread,qk_kernelroot,qk_bridge
OUT=os.path.join(ROOT,'temp','h409_dtb_exact.txt')

def say(s):
    print(s,flush=True)
    with open(OUT,'a',encoding='ascii') as f:f.write(s+'\n')

open(OUT,'w').close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
g=gio.Gio(chunk=0x1000)
mr=qk_gdrv_mapread.install(g);g.read_phys=mr.read
pid=qk_bridge.find_pid()[0]
nt=qk_kernelroot.module_base()
psva=nt+qk_kernelroot.export_rva(nt,b'PsInitialSystemProcess')
say('valid kernel map=%#x PsInitialSystemProcess=%#x PID=%d'%(nt,psva,pid))
g.close()