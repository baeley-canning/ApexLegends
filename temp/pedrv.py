"""pedrv.py -- tiny PE section map so driver code can be addressed as VA.

drvdisasm.py needs this because gdrv3's sections are not laid out in ascending
VA order in the file, so a single global file<->VA delta is wrong.
"""
import struct


def sections(path):
    d = open(path, "rb").read()
    e = struct.unpack_from("<I", d, 0x3C)[0]
    nt = e + 4
    nsec = struct.unpack_from("<H", d, nt + 2)[0]
    optsz = struct.unpack_from("<H", d, nt + 16)[0]
    sh = nt + 20 + optsz
    out = []
    for i in range(nsec):
        raw_name = d[sh + i * 40:sh + i * 40 + 8].rstrip(b"\0")
        vsize, va, rsize, raw = struct.unpack_from("<IIII", d, sh + i * 40 + 8)
        out.append((raw_name.decode("latin1"), va, max(vsize, rsize), raw, rsize))
    return d, out


def off2va(path, off):
    _d, secs = sections(path)
    for _n, va, _vs, raw, rsize in secs:
        if raw <= off < raw + rsize:
            return va + (off - raw)
    raise KeyError("file offset %#x is in no section" % off)


def va2off(path, va):
    _d, secs = sections(path)
    for _n, sva, vs, raw, rsize in secs:
        if sva <= va < sva + vs:
            return raw + (va - sva)
    raise KeyError("va %#x is in no section" % va)


def dump_sections(path):
    _d, secs = sections(path)
    return ["  %-8s va=%#010x vsz=%#08x raw=%#08x rsz=%#08x"
            % (n, va, vs, raw, rsize) for n, va, vs, raw, rsize in secs]
