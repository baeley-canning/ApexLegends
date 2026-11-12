r"""h401 supplement -- native OS driver module order / kernel address proof.
Read-only ordinary query printing, to avoid guessing ModuleInformation offsets.
No raw RAM reads in this helper and no game memory contact.
"""
import ctypes as C
import os
import struct
import subprocess

root=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
a=subprocess.check_output(["powershell","-NoProfile","-Command",
                          "(Get-Process -Name r5apex_dx12 -ErrorAction Stop).Id"],
                         text=True)
pid=int(a.strip())
n=1<<20;b=C.create_string_buffer(n);need=C.c_ulong()
C.windll.ntdll.NtQuerySystemInformation(11,b,n,C.byref(need))
count=struct.unpack_from("<I",b.raw,0)[0]
print("current Apex id",pid,"moduleCount",count)
for i in range(3):
    o=8+16+i*0x128
    print("record",i,"base",hex(struct.unpack_from("<Q",b.raw,o)[0]),
        "imageSize",hex(struct.unpack_from("<I",b.raw,o+8)[0]),
        b.raw[o+24:].split(b"\0")[0])