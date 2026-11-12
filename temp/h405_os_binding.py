r"""h405 -- OS provided exact EPROCESS via uintptr handle table.
One inverted PID field is not an image anchor/physical match.
If owner matches, collect objects and decode exact DTB by proper VA translation.
"""
import ctypes as C
import os,struct,sys,time
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,'ext'))
import gio,dumplive as dl,qk_va,qk_gdrv_mapread,qk_bridge
OUT=os.path.join(ROOT,'temp','h405_os_binding.txt')
def say(s):
    print(s,flush=True)
    with open(OUT,'a',encoding='ascii') as f:f.write(s+'\n')
open(OUT,'w').close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
pid=qk_bridge.find_pid()[0]
k=C.windll.kernel32;k.OpenProcess.restype=C.c_void_p
k.OpenProcess.argtypes=[C.c_ulong,C.c_int,C.c_ulong]
tgt=k.OpenProcess(0x1000,False,pid)
me=os.getpid()
say('target PID=%d owner=%d handle=%#x'%(pid,me,tgt))
n=8<<20
buf=C.create_string_buffer(n);need=C.c_ulong()
st=C.windll.ntdll.NtQuerySystemInformation(64,buf,n,C.byref(need))
if st==0xC0000004:
    buf=C.create_string_buffer(need.value+65536)
    st=C.windll.ntdll.NtQuerySystemInformation(64,buf,need.value,C.byref(need))
listp=[]
if st==0:
    for i in range(struct.unpack_from('<Q',buf.raw,0)[0]):
        offset=16+40*i
        obj,owner,value,access,bt,ti,attrs,res=struct.unpack_from('<QQQIHHII',buf.raw,offset)
        if owner==me and value==tgt:
            say('MATCH obj=%#x owner=%d handle=%#x access=%#x type=%d'%(obj,owner,value,access,ti))
            listp.append(obj)
        if owner==me and ti==7 and len(listp)<4:
            say('PROCESS_HANDLE obj=%#x owner=%d handle=%#x access=%#x'%(obj,owner,value,access))
else:say('raw query failed status=%#x'%st)
with open(os.path.join(ROOT,'temp','h405_targets.txt'),'w',encoding='ascii') as f:f.write('\n'.join(hex(p) for p in listp))
say('objects=%d'%len(listp))