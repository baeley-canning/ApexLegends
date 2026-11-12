r"""h404 -- exact OS EPROCESS through native extended handle table.
The current Apex open-process query handle is the owner of the game object.
No reads or writes through that handle; it is essentially identity evidence.
gdrv3 mapK is only used for real-page reads. Proven current layouts.
"""
import ctypes as C
import os
import struct
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio
import dumplive as dl
import qk_gdrv_mapread
import qk_va
import qk_bridge

OUT=os.path.join(ROOT,"temp","h404_final_object.txt")
def say(s):
    print(s,flush=True)
    with open(OUT,"a",encoding="ascii") as f:f.write(s+"\n")

open(OUT,"w").close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
pid=qk_bridge.find_pid()[0]
k=C.windll.kernel32;k.OpenProcess.argtypes=[C.c_ulong,C.c_int,C.c_ulong]
k.OpenProcess.restype=C.c_void_p
h=k.OpenProcess(0x1000,False,pid)
target_handle=h
self_pid=os.getpid()
say('game PID=%d handle=%#x self_pid=%d'%(pid,h,self_pid))
b=C.create_string_buffer(8<<20);need=C.c_ulong()
st=C.windll.ntdll.NtQuerySystemInformation(64,b,len(b),C.byref(need))
if st!=0:
    b=C.create_string_buffer(need.value+65536)
    st=C.windll.ntdll.NtQuerySystemInformation(64,b,need.value,C.byref(need))
say('native table status=%#x entries=%d'%(st&0xffffffff,
      struct.unpack_from("<Q",b.raw,0)[0]))
obj=None
if st==0:
    for i in range(struct.unpack_from('<Q',b.raw,0)[0]):
        o=16+i*40
        pass
        if owner==self_pid and val==target_handle and ti==7:
            say('FOUND object=%#x owner=%d handle=%#x access=%#x type=%d'%(obj,owner,val,access,ti))
            break
        obj=None
    if not obj:
        for i in range(struct.unpack_from('<Q',b.raw,0)[0]):
            o=16+i*40
            obj,owner,val,access,bt,ti,attrs,res=struct.unpack_from("<QQQIHHII",b.raw,o)
            if owner==self_pid and val==target_handle:
                say('ANY_OBJECT=%#x owner=%d handle=%#x access=%#x type=%d'%(obj,owner,val,access,ti))
                break
            obj=None
g=gio.Gio(chunk=0x1000)
mr=qk_gdrv_mapread.install(g)
g.read_phys=mr.read
try:
    if not obj:
        raise SystemExit(3)
    # Resolve the kernel pointer through a legitimate translation target; old
    # DTB self-ref shapes are not portable. Public PDB says DTB at object+0x28.
    peb=qk_va._peb_va(pid)
    say('peb=%#x object=%#x table root discovery required'%(peb,obj))
    # retain as evidence for direct next stage; no DTB claimed until this read
    with open(os.path.join(ROOT,'temp','h404_object_addr.txt'),'w') as f:
        f.write('%#x\n'%obj)
finally:g.close()