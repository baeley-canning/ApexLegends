"""t_g1.py -- P0 gate round 2: write primitive via \\Device\\PhysicalMemory.

gdrv3 verdict from round 1 (out_g0.txt): read-only driver.
  - 0xC3502014 read: PASS (2.5 us/op)
  - 0xC3502004 map : handled but whitelist-limited (err=31 on plain RAM)
  - 0x2800/0x2804/0x2808/0x280C: NOT implemented in this gdrv3 build (err=1)

This gate proves the write path we will actually use:
  H1 open \\Device\\PhysicalMemory elevated
  H2 view of phys 0x1000 reads the same bytes as gdrv3 0xC3502014
  H3 write marker through the view, read back through gdrv3 -> coherent
  H4 restore original bytes
  H5 MsIo64 0x80102040 map / 0x80102044 unmap probes (backup path, whitelist?)
  H6 timing: persistent-view write, map/unmap cycle, gdrv read
"""
import ctypes
import os
import struct
import sys
import time
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio       # noqa: E402
import physmem   # noqa: E402

OUT = os.path.join(HERE, "out_g1.txt")
LOG = []


def log(s):
    LOG.append(s)
    print(s)


kernel32 = gio.kernel32
shell32 = ctypes.WinDLL("shell32", use_last_error=True)
advapi32 = ctypes.WinDLL("advapi32", use_last_error=True)


def elevation():
    tok = wintypes.HANDLE()
    advapi32.OpenProcessToken(kernel32.GetCurrentProcess(), 0x0008,
                              ctypes.byref(tok))
    rl = wintypes.DWORD(0)
    advapi32.GetTokenInformation(tok, 20, ctypes.byref(rl), 4, ctypes.byref(rl))
    kernel32.CloseHandle(tok)
    return rl.value


class SHELLEXECUTEINFOW(ctypes.Structure):
    _fields_ = [("cbSize", wintypes.DWORD), ("fMask", wintypes.ULONG),
                ("hwnd", wintypes.HWND), ("lpVerb", wintypes.LPCWSTR),
                ("lpParameters", wintypes.LPCWSTR),
                ("lpDirectory", wintypes.LPCWSTR), ("nShow", ctypes.c_int),
                ("hInstApp", wintypes.HINSTANCE), ("lpIDList", wintypes.LPVOID),
                ("lpClass", wintypes.LPCWSTR), ("hkeyClass", wintypes.HKEY),
                ("dwHotKey", wintypes.DWORD), ("hIcon", wintypes.HANDLE),
                ("hProcess", wintypes.HANDLE)]


def run_elevated():
    sei = SHELLEXECUTEINFOW()
    sei.cbSize = ctypes.sizeof(sei)
    sei.fMask = 0x00000040
    sei.lpVerb = "runas"
    sei.lpFile = sys.executable
    sei.lpParameters = '"%s" --elevated' % os.path.abspath(sys.argv[0])
    sei.lpDirectory = HERE
    sei.nShow = 1
    if not shell32.ShellExecuteExW(ctypes.byref(sei)):
        return "ShellExecuteExW failed err=%d" % ctypes.get_last_error()
    kernel32.WaitForSingleObject(sei.hProcess, 240000)
    code = wintypes.DWORD(0)
    kernel32.GetExitCodeProcess(sei.hProcess, ctypes.byref(code))
    kernel32.CloseHandle(sei.hProcess)
    return "elevated child finished, exit=%d" % code.value


def elevated_main():
    verdicts = []
    log("elevation=%d" % elevation())
    try:
        g = gio.Gio()
    except OSError as e:
        log("FATAL gio: %s" % e)
        open(OUT, "w").write("\n".join(LOG) + "\n")
        return 1

    base = g.read_phys(0x1000, 0x40)
    log("gdrv read 0x1000[0:16] = %s" % base[:16].hex(" "))

    # ---- H1 open physical memory
    try:
        pm = physmem.PhysMem()
        log("H1 \\Device\\PhysicalMemory opened, handle=%#x" % (pm.h or 0))
        verdicts.append(("H1 open physmem", True))
    except OSError as e:
        log("H1 FAILED: %s" % e)
        verdicts.append(("H1 open physmem", False))
        open(OUT, "w").write("\n".join(LOG) + "\n")
        return 1

    # ---- H2 view read == gdrv read
    try:
        data = pm.read(0x1000, 0x40)
        log("H2 physmem view read[0:16]  = %s" % data[:16].hex(" "))
        verdicts.append(("H2 physmem==gdrv read", data == base))
    except OSError as e:
        log("H2 FAILED: %s" % e)
        verdicts.append(("H2 physmem==gdrv read", False))

    # ---- H3/H4 write coherency + restore
    try:
        orig = pm.read(0x1010, 8)
        marker = struct.pack("<Q", 0x1D0A5E1A1C0FFEE0)
        pm.write(0x1010, marker)
        via_pm = pm.read(0x1010, 8)
        via_gdrv = g.read_phys(0x1010, 8)
        pm.write(0x1010, orig)
        restored = g.read_phys(0x1010, 8)
        log("H3 orig=%s marker-wrote via_pm=%s via_gdrv=%s restored=%s"
            % (orig.hex(), via_pm.hex(), via_gdrv.hex(), restored.hex()))
        verdicts.append(("H3 write coherent", via_gdrv == marker))
        verdicts.append(("H4 restore ok", restored == orig))
    except OSError as e:
        log("H3 FAILED: %s" % e)
        verdicts.append(("H3 write coherent", False))

    # ---- H5 MsIo64 probes
    try:
        h = kernel32.CreateFileW(r"\\.\MSIO", gio.GENERIC_READ | gio.GENERIC_WRITE,
                                 0, None, gio.OPEN_EXISTING, 0, None)
        if h and h != gio.INVALID_HANDLE:
            ib = struct.pack("<QQQQQ", 4, 0x1000, 0, 0, 0)
            ob = ctypes.create_string_buffer(0x28)
            got = wintypes.DWORD(0)
            ok = kernel32.DeviceIoControl(h, 0x80102040, ib, 0x28, ob, 0x28,
                                          ctypes.byref(got), None)
            err = ctypes.get_last_error()
            vals = struct.unpack("<QQQQQ", ob.raw[:0x28])
            log("H5 MsIo map ok=%s err=%d info=%d out=%s"
                % (ok, err, got.value, " ".join("%#x" % v for v in vals)))
            if ok:
                va = vals[3]
                if va:
                    sample = ctypes.string_at(va, 4)
                    log("   via MsIo VA %#x: %s (gdrv: %s)"
                        % (va, sample.hex(), base[:4].hex()))
                    verdicts.append(("H5 MsIo map==gdrv", sample == base[:4]))
                # unmap probe
                ib2 = struct.pack("<QQQQQ", 0, 0, 0, va, 0)
                ok2 = kernel32.DeviceIoControl(h, 0x80102044, ib2, 0x28, ob, 0x28,
                                               ctypes.byref(got), None)
                log("   MsIo unmap ok=%s err=%d" % (ok2, ctypes.get_last_error()))
            kernel32.CloseHandle(h)
        else:
            log("H5 cannot open \\\\.\\MSIO err=%d" % ctypes.get_last_error())
            verdicts.append(("H5 MsIo map", False))
    except Exception as e:
        log("H5 exception: %s" % e)

    # ---- H6 timing
    t0 = time.perf_counter()
    for _ in range(200):
        pm.write(0x1010, struct.pack("<Q", 0))
    pm.write(0x1010, g.read_phys(0x1010, 8))
    log("H6 persistent-view write u64: %.3f us/op"
        % ((time.perf_counter() - t0) * 1e6 / 200))
    t0 = time.perf_counter()
    for _ in range(30):
        base, _sz = pm.views.pop(0)
        physmem.ntdll.NtUnmapViewOfSection(physmem.CURPROC, base)
        pm.map_block(0)
    log("H6 real map+unmap cycle: %.2f us" % ((time.perf_counter() - t0) * 1e6 / 30))
    t0 = time.perf_counter()
    for _ in range(200):
        g.u64(0x1000)
    log("H6 gdrv read u64: %.2f us/op" % ((time.perf_counter() - t0) * 1e6 / 200))

    pm.close()
    g.close()
    log("")
    log("=== VERDICTS ===")
    for name, res in verdicts:
        log("  %-24s %s" % (name, {True: "PASS", False: "FAIL"}.get(res, "n/a")))
    open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
    return 0


def main():
    if elevation() == 1 or "--elevated" in sys.argv:
        code = elevated_main()
    else:
        print(run_elevated())
        code = 0
        if os.path.exists(OUT):
            print("--- %s" % OUT)
            print(open(OUT, encoding="utf-8").read())
    return code


if __name__ == "__main__":
    sys.exit(main())
