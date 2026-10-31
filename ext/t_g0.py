"""t_g0.py -- P0 transport gate for the glow-only stack (ext/gio.py).

Self-elevates (ShellExecuteW runas), runs the gate sequence and writes
out_g0.txt next to this script, because elevated children lose the console.

Gates:
  G1 baseline 0xC3502014 read of low RAM                 (known-good sanity)
  G2 0xC3502004 map of a RAM page == 0xC3502014 bytes    (map works, same bytes)
  G3 0xC350280C translate: user VA / kernel VA probes    (does it work at all,
                                                         does it take kernel VAs)
  G4 0xC3502800/0x2804 kernel alloc/free probe           (gives a safe PA+VA pair)
  G5 0xC3502808 copy user->phys, both field orders       (write primitive?)
  G6 write coherency through 0xC3502004 mapping          (glow write path verdict)
  G7 0xC3502019 kernel-mapping probe
  G8 per-IOCTL timing
Every write in this probe targets either a page we own (translated user buffer)
or the kernel page returned by 0xC3502800 -- never arbitrary RAM.
"""
import ctypes
import os
import struct
import sys
import time
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

OUT = os.path.join(HERE, "out_g0.txt")
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
    advapi32.GetTokenInformation(tok, 20, ctypes.byref(rl), 4,
                                 ctypes.byref(rl))
    kernel32.CloseHandle(tok)
    return rl.value, rl.value


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
    elev, _ = elevation()
    log("elevation=%d  ram_top=%#x" % (elev, gio.installed_ram_bytes()))
    verdicts = []
    try:
        g = gio.Gio()
    except OSError as e:
        log("FATAL: %s" % e)
        open(OUT, "w").write("\n".join(LOG) + "\n")
        return 1

    owned_pa = None       # PA of a page we may write to
    alloc = None

    # ---- G1 baseline read
    try:
        d = g.read_phys(0x1000, 0x40)
        log("G1 read phys 0x1000: %s" % d[:16].hex(" "))
        verdicts.append(("G1 phys read", bool(any(d))))
        base_read = d
    except OSError as e:
        log("G1 FAILED: %s" % e)
        verdicts.append(("G1 phys read", False))
        base_read = b""

    # ---- G2 map vs read
    map_ok = False
    try:
        va = g.map_phys(0x1000, 0x1000)
        mapped = ctypes.string_at(va, 0x40)
        log("G2 map 0x1000 -> va=%#x  mapped[0:16]=%s" % (va, mapped[:16].hex(" ")))
        same = bool(base_read) and mapped == base_read
        verdicts.append(("G2 map == read", same))
        map_ok = True
        g.unmap(va, 0x1000)
    except OSError as e:
        log("G2 FAILED: %s" % e)
        verdicts.append(("G2 map == read", False))

    # ---- locked user buffer for translate/write tests
    ubuf = gio.alloc_locked(0x2000)
    ctypes.memset(ubuf, 0x5A, 0x2000)
    log("locked user buffer at %#x" % ubuf)

    # ---- G3 translate probes
    tr_ok_user = tr_ok_kern = False
    for label, va in [("user  ubuf", ubuf),
                      ("user  scratch", g.dst),
                      ("kern  KUSD", 0xFFFFF78000000000)]:
        ok, res = g.translate(va)
        log("G3 translate %-13s %#x -> ok=%s res=%s"
            % (label, va, ok, ("err=%s" % res) if not ok else "%#x" % res))
        if ok and va == ubuf:
            tr_ok_user = True
            owned_pa = res & ~0xFFF
        if ok and va == 0xFFFFF78000000000:
            tr_ok_kern = True
    verdicts.append(("G3 translate works", tr_ok_user or tr_ok_kern))
    verdicts.append(("G3 translate kernel VA", tr_ok_kern))

    # ---- G4 kernel alloc/free
    for size in (0x1000, 0x2000, 0x4000):
        ok, err, alloc = g.kernel_alloc(size)
        log("G4 kernel_alloc(%#x) ok=%s err=%s out=%s"
            % (size, ok, err, ("va=%#x b=%#x" % alloc) if ok else "-"))
        if ok:
            break
    if alloc:
        a, b = alloc
        ok, res = g.translate(a)
        log("G4 translate(alloc.va=%#x) -> ok=%s %s ; alloc.b=%#x"
            % (a, ok, ("%#x" % res) if ok else res, b))
        if ok:
            verdicts.append(("G4 translate(alloc.va)==alloc.b",
                             (res & ~0xFFF) == (b & ~0xFFF)))
    verdicts.append(("G4 kernel_alloc", bool(alloc)))

    # ---- G5 0x2808 copy user->phys, both field orders
    if alloc:
        pa = alloc[1] & ~0xFFF
        magic = struct.pack("<Q", 0x4142434445464748)
        ctypes.memset(ubuf, 0, 0x1000)
        ctypes.memmove(ubuf, magic, 8)
        g.read_phys(pa, 0x40)  # warm/verify the PA is readable
        for order, (arg1, arg2) in [("a=va,b=pa", (ubuf, pa)),
                                    ("a=pa,b=va", (pa, ubuf))]:
            ok, err = g.copy_user_to_phys(arg1, arg2, 8)
            back = g.read_phys(pa, 8)
            hit = back == magic
            log("G5 0x2808 order=%-8s ok=%s err=%s phys=%s hit=%s"
                % (order, ok, err, back.hex(), hit))
            if hit:
                verdicts.append(("G5 0x2808 write (%s)" % order, True))
                ctypes.memset(ubuf, 0, 8)
                g.copy_user_to_phys(arg1, arg2, 8)   # restore zeros
                break
        else:
            verdicts.append(("G5 0x2808 write", False))
    else:
        verdicts.append(("G5 0x2808 write", None))

    # ---- G6 write coherency through mapping
    if map_ok and (owned_pa is not None or alloc):
        pa = owned_pa if owned_pa is not None else alloc[1] & ~0xFFF
        orig = g.read_phys(pa, 8)
        va = g.map_phys(pa, 0x1000)
        marker = struct.pack("<Q", 0xDED1C0DEDEADBEED)
        ctypes.memmove(va, marker, 8)
        via_map = ctypes.string_at(va, 8)
        via_read = g.read_phys(pa, 8)
        ctypes.memmove(va, orig, 8)      # restore
        after = g.read_phys(pa, 8)
        g.unmap(va, 0x1000)
        log("G6 pa=%#x orig=%s via_map=%s via_read=%s restored=%s"
            % (pa, orig.hex(), via_map.hex(), via_read.hex(), after.hex()))
        verdicts.append(("G6 map-write coherent",
                         via_read == marker and after == orig))
    else:
        verdicts.append(("G6 map-write coherent", None))

    # ---- G7 0xC3502019 kernel mapping probe
    try:
        ok, err, kva = g.map_kernel(0x1000, 0x1000, g.dst)
        log("G7 map_kernel ok=%s err=%s out=%s" % (ok, err, hex(kva) if kva else "-"))
        verdicts.append(("G7 0x2019 probe", bool(ok)))
    except Exception as e:
        log("G7 exception: %s" % e)
        verdicts.append(("G7 0x2019 probe", False))

    # ---- G8 timing
    t0 = time.perf_counter()
    N = 200
    for _ in range(N):
        g.u64(0x1000)
    log("G8 read u64: %.2f us/op (%d ops)" % ((time.perf_counter() - t0) * 1e6 / N, N))
    if map_ok:
        t0 = time.perf_counter()
        for _ in range(30):
            va = g.map_phys(0x1000, 0x1000)
            g.unmap(va, 0x1000)
        log("G8 map+unmap: %.2f us/cycle" % ((time.perf_counter() - t0) * 1e6 / 30))
        pa = owned_pa if owned_pa is not None else (alloc[1] & ~0xFFF if alloc else 0x1000)
        t0 = time.perf_counter()
        for _ in range(200):
            g.write_phys(pa, struct.pack("<Q", 0))
        log("G8 cached write u64: %.2f us/op"
            % ((time.perf_counter() - t0) * 1e6 / 200))
    for code in sorted(g.stats):
        log("  stat %s" % g.stat_line(code))

    # ---- cleanup
    if map_ok and (owned_pa is not None or alloc):
        pa = owned_pa if owned_pa is not None else alloc[1] & ~0xFFF
        orig = g.read_phys(pa, 8)
        g.write_phys(pa, orig)           # undo the G8 zero-writes
    if alloc:
        ok, err = g.kernel_free(alloc[0], alloc[1])
        log("cleanup kernel_free ok=%s err=%s" % (ok, err))
    kernel32.VirtualUnlock(ubuf, 0x2000)
    kernel32.VirtualFree(ubuf, 0, gio.MEM_RELEASE)
    g.close()

    log("")
    log("=== VERDICTS ===")
    for name, res in verdicts:
        log("  %-34s %s" % (name, {True: "PASS", False: "FAIL"}.get(res, "n/a")))
    open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
    return 0


def main():
    elev, rid = elevation()
    print("parent: elevated=%s rid=%#x" % (elev == 1, rid))
    if elev == 1 or "--elevated" in sys.argv:
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
