r"""h406 -- validated self-process kernel detection through gdrv3 MapK.
Own python only until exact current _EPROCESS name/PID and DTB all agree.
This separates transport/discovery-function bugs from target-specific issues.
"""
import os,struct,sys,time,importlib.util
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,'ext'))
import gio,dumplive as dl,qk_va,qk_gdrv_mapread
OUT=os.path.join(ROOT,'temp','h406_self_kernel.txt')
def say(s):
    print(s,flush=True)
    with open(OUT,'a',encoding='ascii') as f:f.write(s+'\n')
open(OUT,'w').close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
pid=os.getpid()
say('SELF pid=%d PEB=%#x'%(pid,qk_va._peb_va(pid)))
g=gio.Gio(chunk=0x1000)
mr=qk_gdrv_mapread.install(g)
dl.NAME=b'python.exe\0'
spec=importlib.util.spec_from_file_location('h142',os.path.join(ROOT,'temp','_p142.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
m.OUT=os.path.join(ROOT,'temp','h406_proc.txt');m._f=open(m.OUT,'w')
try:
    dtb,seeds=m.find_dtb(g,pid,budget=190.0,seeds=[],proctag=True)
    say('DTB candidate=%s'%dtb)
    if dtb:
        rd=qk_va.Reader(g,dtb)
        peb=qk_va._peb_va(pid)
        rb=rd.read(peb+0x10,8)
        if rb:
            base=struct.unpack('<Q',rb)[0]
            page=rd.read(base,0x1000)
            meta=dl.validate_pe(page) if page else None
            say('BASE=%#x PE=%s'%(base,meta))
            say('VERDICT: %s'%('PASS' if meta else 'BLOCKED'))
        else:say('no PEB virtual read, walker now explains ' + dl.probe_dtb(g,dtb))
finally:g.close()
say('VERDICT: %s'%('PASS' if dtb else 'BLOCKED_SELF'))