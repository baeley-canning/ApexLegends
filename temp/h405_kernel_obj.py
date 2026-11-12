r"""h405 -- using the OS-confirmed EPROCESS object (not name-sweep object).

Windows privileged subsystem hides general virtual translation in GIOV3's
public Translate ioctl. MmGetPhysicalAddress is still meaningful in the
system kernel context, so we derive a kernel DTB via Exe entry point VA
using a guarded *PAGE TABLE SHAPE ONLY* lookup, not stale pointer names.
If any candidate finds CR3? No: prove known KVA EPROCESS/object at once,
then get actual process DTB by +0x28 and confirm PEB->PE via real MapK.
"""
import ctypes as C
import os,struct,sys,time
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'ext'))
import gio
import dumplive as dl
import qk_va
import qk_gdrv_mapread

OUT = os.path.join(ROOT, 'temp', 'h405_kernel_obj.txt')
def say(s):
    print(s, flush=True)
    with open(OUT, 'a', encoding='ascii') as f: f.write(s + '\n')

open(OUT, 'w').close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
say('=== known Apex kernel object -> translate DTB gate %s ==='%time.strftime('%Y-%m-%d %H:%M:%S'))
g = gio.Gio(chunk=0x1000)
mr = qk_gdrv_mapread.install(g)
g.read_phys = mr.read
obj = int(open(os.path.join(ROOT,'temp','h404_object_addr.txt')).read().strip(), 16)
say('KOBJ=%#x module window known' % obj)
pids = [14624]
peb = qk_va._peb_va(pids[0])
start = time.time()
found = None
count = 0
try:
    for lo,hi in mr.ranges:
        pa=lo
        while pa+0x1000<=hi and time.time()-start<180:
            try:b=mr.read(pa,0x1000)
            except OSError:
                pa+=0x1000;continue
            high=struct.unpack_from("<Q",b,(obj>>39&511)*8)[0]
            if not high & 1 or (high & 0xFFFFFFFFFF000)==0 or not mr.in_ram(high&0xFFFFFFFFFF000,0x1000):
                pa+=0x1000;continue
            count+=1
            try:
                rd=qk_va.Reader(g,pa)
                # A kernel-based root recognizing a global object structure.
                # DTB flags must be correct THEN name/pid exactly inside object
                name=rd.read(obj+0x338,15)
                if not name:
                    pa += 0x1000
                    continue
                pval=struct.unpack('<Q',read_rd()) if False else None
                rb=rd.read(obj+0x1D0,8)
                if not rb:
                    pa+=0x1000
                    continue
                pval=struct.unpack('<Q',rb)[0]
                if pval==pids[0] and name==b'r5apex_dx12.ex\0':
                    say('ROOT=%#x -> exact game _EPROCESS type/name/pid'%pa)
                    dtb=struct.unpack('<Q',rd.read(obj+0x28,8))[0]
                    if dtb:
                        say('DECODED DTB=%#x'%dtb)
                        nr=qk_va.Reader(g,dtb)
                        raw=nr.read(peb+0x10,8)
                        if raw:
                            base=struct.unpack('<Q',raw)[0]
                            meta=dl.validate_pe(nr.read(base,0x1000))
                            say('PEB base=%#x PE=%s'%(base,meta))
                            if meta:
                                qk_va.save_cache(pids[0],dtb,base)
                                say('VERDICT: PASS - gdrv3 Module virtual read path complete')
                                sys.exit(0)
            except OSError:
                pass
            pa+=0x1000
        if found:break
    say('VERDICT: BLOCKED - root candidate object no PE readbacks tested=%d'%count)
except Exception:
    import traceback;say(traceback.format_exc())
finally:g.close()
say('RESULT: nonvalidated table not trusted')