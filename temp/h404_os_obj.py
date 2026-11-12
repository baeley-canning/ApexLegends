r"""h404 authoritative process EPROCESS from SYSTEM_HANDLE_TABLE_ENTRY_INFO_EX.
Layout: PVOID Object; HANDLE UniqueProcessId; HANDLE HandleValue; HANDLE ReservedQword
or Access as 64-bit value; ULONG TypeIndex; ULONG HandleAttributes; 8 bytes attr.
"""
import ctypes as C
import os,struct,sys,time
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,'ext'))
import gio,dumplive as dl,qk_gdrv_mapread,qk_va,qk_bridge
OUT=os.path.join(ROOT,'temp','h404_os_obj.txt')
def say(s):
    print(s,flush=True)
    with open(OUT,'a',encoding='ascii') as f:f.write(s+'\n')
open(OUT,'w').close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
pid=qk_bridge.find_pid()[0]
k=C.windll.kernel32;k.OpenProcess.restype=C.c_void_p
k.OpenProcess.argtypes=[C.c_ulong,C.c_int,C.c_ulong]
h=k.OpenProcess(0x1000,False,pid)
say('PID=%d QUERY_HANDLE=%#x SELF=%d'%(pid,h,os.getpid()))
buf=C.create_string_buffer(1<<22);need=C.c_ulong()
st=C.windll.ntdll.NtQuerySystemInformation(64,buf,len(buf),C.byref(need))
if st==0xC0000004:
    buf=C.create_string_buffer(need.value+65536)
    st=C.windll.ntdll.NtQuerySystemInformation(64,buf,need.value,C.byref(need))
say('query64_status=%#x expected_bytes=%d'%(st&0xffffffff,need.value))
count=struct.unpack_from('<Q',buf.raw,0)[0]
say('num entries=%d'%count)
objs=set();own=[]
target_handle=h
for i in range(count):
    off=16+i*40
    obj,owner,value,access,btindex,tidx,attrs,res=struct.unpack_from('<QQQIHHII',buf.raw,off)
    if i<3:say('entry=%d object=%#x owner=%d handle=%#x access=%#x type=%d'%(i,obj,owner,value,access,tidx))
    if owner==os.getpid():
        if len(own)<14:
            say('OWNED object=%#x handle=%#x access=%#x type=%d'%(obj,value,access,tidx))
        own.append((obj,value,access,tidx))
        if value==target_handle:objs.add(obj)
say('MATCH objects=%s'%([hex(o) for o in objs]))
g=gio.Gio(chunk=0x1000)
mr=qk_gdrv_mapread.install(g);g.read_phys=mr.read
with open(os.path.join(ROOT,'temp','h404_object_addr.txt'),'w') as f:f.write('\n'.join(hex(o) for o in objs))
g.close()