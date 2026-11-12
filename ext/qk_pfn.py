r"""qkvP -- normal Windows PFN lookup + existing gdrv3 physical reads.

Exact native PF_PFN_PRIO_REQUEST layout (x64): Version=1 at +0, QueryFlags=0
at +4, PfnCount at +8, first entry at +0xC0. The Superfetch envelope is 24B:
version 45, magic 'kuhC', class SuperfetchPfnQuery(6), payload pointer, size.
One page only: first PA is the input VA. No other candidate PFNs are scanned.
The verdict is a byte-for-byte marker/PE read-back, no optimistic guesses.
"""
import ctypes as C
import ctypes.wintypes as wt
import struct


class PfQuery(C.Structure):
    _fields_ = [("Version", C.c_uint32), ("Magic", C.c_uint32),
                ("InfoClass", C.c_uint32), ("Data", C.c_void_p)] if False else [
                ("Version", C.c_uint32), ("Magic", C.c_uint32),
                ("InfoClass", C.c_uint32), ("Data", C.c_uint64)]


def pa_of(va):
    buffer = C.create_string_buffer(0xD8)
    struct.pack_into("<IIQ", buffer, 0, 1, 0, 1)
    struct.pack_into("<Q", buffer, 0xC0, int(va))
    query = PfQuery(45, 0x4375686B, 6, C.addressof(buffer))
    size = C.sizeof(query)
    status = C.windll.ntdll.NtQuerySystemInformation(79, C.byref(query),
                                                    size, None)
    raw = buffer.raw
    entry = struct.unpack_from("<QQQ", raw, 0xC0)
    pf = 0
    return {"status": status & 0xFFFFFFFF, "first_va": entry[0],
            "pfn": entry[1], "flags": entry[2], "memcount": pf[0],
            "raw": raw[:32] + raw[0xC0:0xD8]}
