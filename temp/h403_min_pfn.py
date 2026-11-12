r"""h403 direct SystemSuperfetchInformation PF_PFN_PRIO_REQUEST one PFN.
Caller uses same documented PF_PFN_PRIO_REQUEST version 1 and count 1,
Superfetch information magic 'kuhC' version 45, class SuperfetchPfnQuery.
Local only, no game writes or arbitrary physical scanning.
"""
import ctypes as C
import os,struct,sys
sys.path.insert(0,os.path.join(os.path.dirname(__file__),'..','ext'))
import dumplive as dl
class Q(C.Structure):
    _fields_=[('v',C.c_uint32),('magic',C.c_uint32),('kind',C.c_uint32),
              ('pad',C.c_uint32),('ptr',C.c_uint64),('size',C.c_uint32)]
def see(va):
    raw=C.create_string_buffer(0xd8)
    struct.pack_into('<IIQ',raw.raw,0,1,0,1)
    struct.pack_into('<Q',raw.raw,0xc0,va)
    req=Q(45,0x4375686b,6,0,C.addressof(raw),0xd8)
    need=C.c_ulong()
    status=C.windll.ntdll.NtQuerySystemInformation(79,C.byref(req),C.sizeof(req),C.byref(need))&0xffffffff
    return status,need.value,raw.raw.hex()

open(os.path.join(os.path.dirname(__file__),'h403_min_pfn.txt'),'w').close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
buf=C.create_string_buffer(16)
with open(os.path.join(os.path.dirname(__file__),'h403_min_pfn.txt'),'a',encoding='ascii') as f:f.write(str(see(C.addressof(buf))))