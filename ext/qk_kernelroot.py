r"""Kernel-base based process discovery using only existing GIOV3.

Root discovery no longer guesses arbitrary EPROCESS DTBs. System modules tell
us exact ntoskrnl VA and PsInitialSystemProcess RVA. Candidate PML4s are only
considered if they actually map that kernel VA to a full valid PE.
The result is still fail-closed until complete current-game PE read-back.
"""
import ctypes as C
import os
import struct
import time

import gio
import dumplive as dl
import qk_va
import qk_gdrv_mapread


def module_base():
    data = C.create_string_buffer(1 << 20)
    need = C.c_ulong()
    st = C.windll.ntdll.NtQuerySystemInformation(11, data, C.sizeof(data), C.byref(need))
    if st == 0xC0000004:
        data = C.create_string_buffer(need.value + 0x10000)
        C.windll.ntdll.NtQuerySystemInformation(11, data, len(data), C.byref(need))
    n = struct.unpack_from("<I", data.raw, 0)[0]
    for i in range(n):
        o = 8 + 16 + i * 0x128
        base = struct.unpack_from("<Q", data.raw, o)[0]
        name = data.raw[o+0x38:].split(b"\0", 1)[0]
        if name.endswith(b"ntoskrnl.exe"):
            return base
    raise RuntimeError("no kernel base")


def export_rva(image, name):
    b = open(r"C:\Windows\System32\ntoskrnl.exe", "rb").read()
    e = struct.unpack_from("<I", b, 0x3C)[0]
    opt = e + 24
    ns = struct.unpack_from("<H", b, e+6)[0]
    osz = struct.unpack_from("<H", b, e+20)[0]
    erv = struct.unpack_from("<I", b, opt+0x70)[0]
    secs = [struct.unpack_from("<IIII", b, opt+osz+i*40+8) for i in range(ns)]
    def rva_to_file(rva):
        for vs, va, rs, rp in secs:
            if va <= rva < va + vs:
                return rp+rva-va
        if rva < 0x1000:
            return rva
        raise ValueError("outside export")
    ep = rva_to_file(erv)
    count = struct.unpack_from("<I", b, ep+20)[0]
    names = struct.unpack_from("<I", b, ep+32)[0]
    funcs = struct.unpack_from("<I", b, ep+28)[0]
    ords = struct.unpack_from("<I", b, ep+36)[0]
    for i in range(count):
        r = struct.unpack_from("<I", b, rva_to_file(names)+i*4)[0]
        if b[rva_to_file(r):].split(b"\0", 1)[0] == name:
            return struct.unpack_from("<I", b,
                    rva_to_file(funcs)+struct.unpack_from("<H", b,
                    rva_to_file(ords)+i*2)[0]*4)[0]
    return None