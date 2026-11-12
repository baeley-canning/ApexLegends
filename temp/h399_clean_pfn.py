r"""h399 — small, correct native VA->PFN positive control.
Windows PF_PFN_PRIO_REQUEST + existing gdrv3 MapK. No DTB. No alternate driver.
PfnCount=1, first entry at 0xC0, payload 0xD8, outer version 45 magic 'kuhC'.
Layout of class-specific payload: Version, Height-1, Count, meminfo, entries.
"""
import ctypes as C
import os
import struct
import sys
import time

ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,"ext"))
import gio,dumplive as dl,qk_gdrv_mapread,qk_va,qk_bridge

OUT=os.path.join(ROOT,"temp","h399_clean_pfn.txt")
class Q(C.Structure):
    _pack_=8
    _fields_=[("version",C.c_uint32),("magic",C.c_uint32),
              ("info_class",C.c_uint32),("pad",C.c_uint32),("data",C.c_void_p)]

def say(s):
    print(s,flush=True)
    with open(OUT,"a",encoding="ascii") as f:f.write(s+"\n")

def page_info(va):
    buf=C.create_string_buffer(0xD8)
    struct.pack_into("<IIQ",buf,0,1,0,1)
    struct.pack_into("<Q",buf,0xC0,va)
    query=Q(45,0x4375686B,6,0,C.addressof(buf))
    need=C.c_ulong(0)
    status=C.windll.ntdll.NtQuerySystemInformation(79,C.byref(query),C.sizeof(query),C.byref(need))&0xffffffff
    if status:return {"status":status,"raw":buf.raw[:32]}
    va_out,pfn,flags=struct.unpack_from("<QQQ",buf,0xC0)
    return {"status":0,"va":va_out,"pfn":pfn,"flags":flags,
            "raw":buf.raw[:32]+buf.raw[0xc0:0xd8]}

open(OUT,"w").close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
say("clean native PFN+MapK %s"%time.strftime("%Y-%m-%d %H:%M:%S"))
g=gio.Gio(chunk=0x1000)
mr=qk_gdrv_mapread.install(g)
g.read_phys=mr.read
try:
    marker=C.create_string_buffer(b"PTE-CORRECT-123456789")
    m=page_info(C.addressof(marker))
    say("local query=%s"%m)
    if m["status"]!=0:
        say("VERDICT: BLOCKED - PFN size=%#x needed=%d"%(C.sizeof(query),need.value));sys.exit(3)
    pa=m["va"] if False else (m["pfn"]<<12)|(C.addressof(marker)&0xfff)
    say("pa=%#x offset=%#x"%(pa,pa&0xfff))
    raw=g.read_phys(pa&~0xfff,0x1000)
    match=raw[pa&0xfff:pa&0xfff+22]==b"PTE-CORRECT-123456789"
    say("local control match=%s"%match)
    pid=qk_bridge.find_pid()[0]
    p=qk_va._peb_va(pid)
    say("current pid=%d peb=%#x"%(pid,p))
    m=page_info(p+0x10)
    say("peb query status=%#x raw=%s"%(m["status"],m["raw"].hex()))
    if m["status"]==0:
        pet=m["pfn"] & 0xFFFFFFFFFFFFF
        off=(p+0x10)&0xfff
        page=mr.read((pet<<12),0x1000)
        base=struct.unpack_from("<Q",page,off)[0]
        say("base=%#x"%base)
        pm=page_info(base)
        if not pm["status"]:
            data=mr.read(pm["pfn"]<<12,0x1000)
            meta=dl.validate_pe(data)
            say("RESULT: base=%#x image_pa=%#x PE=%s"%(base,pm["pfn"]<<12,meta))
            say("VERDICT: %s"%("PASS" if meta and meta["size"]==0xDFB8000 else "BLOCKED"))
    say("done - uncertain if no padding needed")
finally:
    g.close()