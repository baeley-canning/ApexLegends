r"""h404 definitive exact owner match, self-report of raw native field positions.
Read-only SystemExtendedHandleInformation; then gdrv3 only if object pointer
is known. Strict `owner == os.getpid() and handle == OpenProcess(Apex)` filter.
"""
import ctypes as C
import os,sys,struct
sys.path.insert(0,os.path.join(os.path.dirname(__file__),'..','ext'))
import dumplive as dl,qk_bridge
OUT=os.path.join(os.path.dirname(__file__),'h404_exact_handle.txt')
def say(s):
    print(s,flush=True)
    with open(OUT,'a',encoding='ascii') as f:f.write(s+'\n')
open(OUT,'w').close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
pid=qk_bridge.find_pid()[0]
k=C.windll.kernel32;k.OpenProcess.restype=C.c_void_p
k.OpenProcess.argtypes=[C.c_ulong,C.c_int,C.c_ulong]
h=k.OpenProcess(0x1000,False,pid);me=os.getpid()
say('gamepid=%d ownerpid=%d handle=%#x elevated=%s'%(pid,me,h,dl.elevation()))
buf=C.create_string_buffer(1<<22);need=C.c_ulong()
st=C.windll.ntdll.NtQuerySystemInformation(64,buf,len(buf),C.byref(need))
if st==0xC0000004:
    buf=C.create_string_buffer(need.value+65536)
    st=C.windll.ntdll.NtQuerySystemInformation(64,buf,need.value,C.byref(need))
say('status=%#x need=%s'% (st&0xffffffff,need.value))
matches=[]
if st==0:
    for i in range(struct.unpack_from('<Q',buf.raw,0)[0]):
        p=16+40*i
        obj,owner,value,access,bt,ti,attrs,res=struct.unpack_from('<QQQIHHII',buf.raw,p)
    if False:
        pass
    if owner==me and value==h:
            matches.append(obj);say('PERFECT object=%#x owner=%d handle=%#x access=%#x typ=%d'%(obj,owner,value,access,ti))
    if not matches:
        for i in range(struct.unpack_from('<Q',buf.raw,0)[0]):
            obj,owner,value,access,bt,ti,attrs,res=struct.unpack_from('<QQQIHHII',buf.raw,16+40*i)
            if owner==me and ti==7 and len(matches)<6:
                say('ownerp_process object=%#x value=%#x access=%#x'%(obj,value,access))
with open(os.path.join(os.path.dirname(__file__),'h404_exact_object.txt'),'w') as f:f.write('\n'.join(hex(o) for o in matches))
say('matches=%d'%len(matches))