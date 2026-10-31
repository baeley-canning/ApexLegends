r"""elev_probe.py -- open \\.\GIOV3 as Administrator and exercise the phys-read IOCTL.

Why elevation: gdrv3.sys embeds the UTF-16 SDDL string
    D:P(A;;GA;;;SY)(A;;GA;;;BA)
i.e. only NT AUTHORITY\SYSTEM and BUILTIN\Administrators get GENERIC_ALL, and the
"P" (protected) flag blocks inheritance.  A non-elevated token therefore cannot
even open the device (err=5 / ERROR_ACCESS_DENIED), which matches open_probe.txt.

This script re-launches itself through ShellExecuteW("runas") and the elevated
child writes elev_probe.txt, so the normal-token shell can read the verdict.

Recovered gdrv3 handler (RVA ~0x3696) for IOCTL 0xC3502400:
    if (in_len < 0x18) return 0xC000009A
    mapped = MmMapIoSpace(in->phys, in->size, MmNonCached)
    memcpy(in->dst, mapped, in->size);
    MmUnmapIoSpace(mapped, in->size);
    struct GIOV3_READ { u64 phys; u32 size; u32 pad; void *dst; };
"""
import ctypes
import os
import struct
import sys
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "elev_probe.txt")

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
adv = ctypes.WinDLL("advapi32", use_last_error=True)
shell32 = ctypes.WinDLL("shell32", use_last_error=True)

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3
INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value
MEM_COMMIT = 0x1000
MEM_RESERVE = 0x2000
MEM_RELEASE = 0x8000
PAGE_READWRITE = 0x04

k32.CreateFileW.restype = wintypes.HANDLE
k32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                             wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD,
                             wintypes.HANDLE]
k32.DeviceIoControl.restype = wintypes.BOOL
k32.DeviceIoControl.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPVOID,
                                 wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD,
                                 ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
k32.VirtualAlloc.restype = wintypes.LPVOID
k32.VirtualAlloc.argtypes = [wintypes.LPVOID, ctypes.c_size_t, wintypes.DWORD,
                              wintypes.DWORD]
k32.VirtualFree.restype = wintypes.BOOL
k32.VirtualFree.argtypes = [wintypes.LPVOID, ctypes.c_size_t, wintypes.DWORD]
k32.VirtualLock.restype = wintypes.BOOL
k32.VirtualLock.argtypes = [wintypes.LPVOID, ctypes.c_size_t]
k32.CloseHandle.restype = wintypes.BOOL
k32.CloseHandle.argtypes = [wintypes.HANDLE]
k32.GetCurrentProcess.restype = wintypes.HANDLE
adv.OpenProcessToken.restype = wintypes.BOOL
adv.OpenProcessToken.argtypes = [wintypes.HANDLE, wintypes.DWORD,
                                  ctypes.POINTER(wintypes.HANDLE)]
adv.GetTokenInformation.restype = wintypes.BOOL

TOKEN_QUERY = 0x0008
TokenElevation = 20
TokenIntegrityLevel = 25

# {u64 phys; u32 size; u32 pad; void *dst} -> memcpy(dst, MmMapIoSpace(phys), size)
# NOTE: 0xC3502400 is NOT this function.  read_probe.py proved 0x2400 writes only
# 4 bytes (it echoes in->phys back into the output buffer, Information == 4) and
# never touches dst.  That is why the first probe run reported all-zero data:
# dst was a fresh (already zero) VirtualAlloc and was simply never written.
# 0xC3502014 really does write dst, and reports Information == 0.
IOCTL_MAP_READ = 0xC3502014
IOCTL_ECHO = 0xC3502400

TARGETS = [(r"\\.\GIOV3", "gdrv3 (YCC)"), (r"\\.\MsIo", "MsIo64"),
           (r"\\.\MSIO", "MsIo64 upper"), (r"\\.\gio", "gio?")]


def elevation():
    tok = wintypes.HANDLE()
    if not adv.OpenProcessToken(k32.GetCurrentProcess(), TOKEN_QUERY,
                                ctypes.byref(tok)):
        return -1, 0
    buf = ctypes.create_string_buffer(64)
    ln = wintypes.DWORD(0)
    elev = -1
    if adv.GetTokenInformation(tok, TokenElevation, buf, 64, ctypes.byref(ln)):
        elev = ctypes.cast(buf, ctypes.POINTER(wintypes.DWORD))[0]
    rid = 0
    if adv.GetTokenInformation(tok, TokenIntegrityLevel, buf, 64,
                               ctypes.byref(ln)):
        sid = ctypes.cast(buf, ctypes.POINTER(ctypes.c_void_p))[0]
        if sid:
            cnt = ctypes.cast(ctypes.c_void_p(sid),
                              ctypes.POINTER(ctypes.c_ubyte))[1]
            rid = ctypes.cast(ctypes.c_void_p(sid + 8 + 4 * (cnt - 1)),
                              ctypes.POINTER(wintypes.DWORD))[0]
    k32.CloseHandle(tok)
    return elev, rid


class SHELLEXECUTEINFOW(ctypes.Structure):
    _fields_ = [("cbSize", wintypes.DWORD),
                ("fMask", wintypes.ULONG),
                ("hwnd", wintypes.HWND),
                ("lpVerb", wintypes.LPCWSTR),
                ("lpFile", wintypes.LPCWSTR),
                ("lpParameters", wintypes.LPCWSTR),
                ("lpDirectory", wintypes.LPCWSTR),
                ("nShow", ctypes.c_int),
                ("hInstApp", wintypes.HINSTANCE),
                ("lpIDList", wintypes.LPVOID),
                ("lpClass", wintypes.LPCWSTR),
                ("hkeyClass", wintypes.HKEY),
                ("dwHotKey", wintypes.DWORD),
                ("hIcon", wintypes.HANDLE),
                ("hProcess", wintypes.HANDLE)]


def run_elevated(script=None, extra="--elevated"):
    """Re-launch `script` (default: the running script) elevated and wait.

    NOTE: must not hardcode __file__ -- this module is imported by other probes
    (read_probe.py), which need themselves relaunched, not elev_probe.py.
    """
    if script is None:
        script = os.path.abspath(sys.argv[0])
    sei = SHELLEXECUTEINFOW()
    sei.cbSize = ctypes.sizeof(sei)
    sei.fMask = 0x00000040          # SEE_MASK_NOCLOSEPROCESS
    sei.lpVerb = "runas"
    sei.lpFile = sys.executable
    sei.lpParameters = '"%s" %s' % (os.path.abspath(script), extra)
    sei.lpDirectory = HERE
    sei.nShow = 1                   # SW_SHOWNORMAL
    if not shell32.ShellExecuteExW(ctypes.byref(sei)):
        return "ShellExecuteExW failed err=%d (%s)" % (
            ctypes.get_last_error(), ctypes.FormatError().strip())
    k32.WaitForSingleObject(sei.hProcess, 180000)
    code = wintypes.DWORD(0)
    k32.GetExitCodeProcess(sei.hProcess, ctypes.byref(code))
    k32.CloseHandle(sei.hProcess)
    return "elevated child finished, exit=%d" % code.value


# ---------------------------------------------------------------- phys helpers
def alloc_locked(size):
    p = k32.VirtualAlloc(None, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE)
    if not p:
        raise OSError("VirtualAlloc failed %d" % ctypes.get_last_error())
    k32.VirtualLock(p, size)
    return p


def ioctl_map_read(h, phys, size, dst, in_len=0x18, out_len=None):
    """METHOD_BUFFERED ioctl: driver does memcpy(in->dst, mapped, in->size).

    The kernel side reports Information = in->size, so the user output buffer
    must be at least that big or DeviceIoControl fails with 122
    (ERROR_INSUFFICIENT_BUFFER) even though the copy already happened.
    """
    if out_len is None:
        out_len = max(size, 1)
    ib = ctypes.create_string_buffer(0x20)
    struct.pack_into("<QII", ib, 0, phys & 0xFFFFFFFFFFFFFFFF, size, 0)
    if in_len >= 0x18:
        struct.pack_into("<Q", ib, 0x10, dst)
    ob = ctypes.create_string_buffer(out_len)
    ret = wintypes.DWORD(0)
    ok = k32.DeviceIoControl(h, IOCTL_MAP_READ, ib, in_len, ob, out_len,
                             ctypes.byref(ret), None)
    err = 0 if ok else ctypes.get_last_error()
    return bool(ok), err, ret.value


def read_phys(h, phys, size):
    dst = alloc_locked(size)
    try:
        ok, err, _ = ioctl_map_read(h, phys, size, dst)
        return ok, err, ctypes.string_at(dst, size) if ok else b""
    finally:
        k32.VirtualFree(dst, 0, MEM_RELEASE)


def hexdump(data, base=0, width=16, limit=0x40):
    out = []
    for off in range(0, min(limit, len(data)), width):
        c = data[off:off + width]
        out.append("  %08x  %s  |%s|" % (
            base + off,
            " ".join("%02x" % b for b in c).ljust(width * 3 - 1),
            "".join(chr(b) if 32 <= b < 127 else "." for b in c)))
    return out


# ------------------------------------------------------------------ elevated
def elevated_main():
    fh = open(OUT, "w", encoding="utf-8")

    def log(s=""):
        fh.write(s + "\n")
        fh.flush()
        print(s)

    elev, rid = elevation()
    log("=== child identity: elevated=%s integrity_rid=%#x pid=%d"
        % (elev == 1, rid, os.getpid()))

    log("=== open matrix")
    handles = {}
    for path, who in TARGETS:
        got = None
        for an, av in (("R|W", GENERIC_READ | GENERIC_WRITE),
                       ("0", 0)):
            for sn, sv in (("all", 0x7), ("none", 0)):
                ctypes.set_last_error(0)
                h = k32.CreateFileW(path, av, sv, None, OPEN_EXISTING, 0, None)
                if h and h != INVALID_HANDLE_VALUE:
                    log("  %-12s (%-9s) access=%-4s share=%-4s -> OK handle=%#x"
                        % (path, who, an, sn, h))
                    got = (h, av, sv)
                    break
                log("  %-12s (%-9s) access=%-4s share=%-4s -> err=%d (%s)"
                    % (path, who, an, sn, ctypes.get_last_error(),
                       ctypes.FormatError().strip()))
            if got:
                break
        if got:
            handles[path] = got

    if not handles:
        log("VERDICT: still cannot open even elevated -- not a plain BA/SY DACL")
        fh.close()
        return 1

    for path, (h, av, sv) in handles.items():
        log("=== phys reads via %s (handle %#x)" % (path, h))
        probes = [("IVT", 0x00000000, 0x200),
                  ("BDA", 0x00000400, 0x100),
                  ("EBDA", 0x0009F000, 0x100),
                  ("VGA", 0x000A0000, 0x100),
                  ("ROM", 0x000F0000, 0x100),
                  ("LAPIC", 0xFEE00000, 0x40),
                  ("low1M", 0x00100000, 0x100)]
        good = 0
        blobs = {}
        for label, phys, size in probes:
            ok, err, data = read_phys(h, phys, size)
            nz = sum(1 for b in data if b)
            if ok:
                good += 1
                blobs[label] = data
            log("  %-6s phys=%#011x size=%#05x ok=%-5s err=%-3d nonzero=%3d/%3d"
                % (label, phys, size, ok, err, nz, size))
            if ok and label in ("IVT", "ROM"):
                for ln in hexdump(data, phys, limit=0x30):
                    log(ln)
        log("  accepted %d/%d" % (good, len(probes)))

        if "BDA" in blobs:
            mem_kb = struct.unpack_from("<H", blobs["BDA"], 0x13)[0]
            log("  BDA 0x413 base-mem = %#x KB (expect 0x100..0x7800)" % mem_kb)
        if "IVT" in blobs:
            vec = [struct.unpack_from("<H", blobs["IVT"], i * 4)[0]
                   for i in range(8)]
            log("  IVT first 8 segments = %s" % " ".join("%04x" % v for v in vec))

        # independent check: ACPI RSDP ("RSD PTR ") sits below 1 MiB
        found = None
        for pa in range(0x000E0000, 0x00100000, 0x1000):
            ok, err, data = read_phys(h, pa, 0x1000)
            if ok and b"RSD PTR " in data:
                found = (pa + data.index(b"RSD PTR "), data)
                break
        if found:
            log("  ACPI RSDP signature at phys %#x -> %r"
                % (found[0], found[1][:16]))
        else:
            log("  ACPI RSDP scan 0xE0000-0xFFFFF: not found")

        ok1, _, d1 = read_phys(h, 0x0, 0x200)
        ok2, _, d2 = read_phys(h, 0x0, 0x200)
        log("  repeat read 0x0: ok=%s/%s identical=%s"
            % (ok1, ok2, bool(d1) and d1 == d2))
        dst = alloc_locked(0x100)
        ok, err, _ = ioctl_map_read(h, 0x1000, 0x100, dst, in_len=8)
        log("  short in_len=8 -> ok=%s err=%d (%s)"
            % (ok, err, ctypes.FormatError(err).strip()))
        k32.VirtualFree(dst, 0, MEM_RELEASE)
        log("  VERDICT %s: %d/%d reads accepted%s"
            % (path, good, len(probes),
               " -- PHYS READ LIVE" if good == len(probes) else ""))
        k32.CloseHandle(h)

    fh.close()
    return 0


def main():
    elev, rid = elevation()
    print("parent: elevated=%s integrity_rid=%#x" % (elev == 1, rid))
    if elev == 1 or "--elevated" in sys.argv:
        return elevated_main()
    print(run_elevated())
    if os.path.exists(OUT):
        print("--- %s" % OUT)
        print(open(OUT, encoding="utf-8").read())
    return 0


if __name__ == "__main__":
    sys.exit(main())
