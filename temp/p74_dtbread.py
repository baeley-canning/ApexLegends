r"""p74_dtbread.py -- why does a page-table frame not read while data pages do?

Calibration from p72: the live EPROCESS of pid 19912 was found byte-correct
(base 0x4a3410080, name "Code.exe") but its DirectoryTableBase 0x4a6be3000
reports unreadable, and the fingerprint page for the same process agreed.  The
EPROCESS page itself reads fine every time.  So the fault is a property of the
FRAME, not of the process, and it is not Apex-specific.

This probe parts:
  A  control read of the EPROCESS page                    (expect OK)
  B  the DTB frame, errno printed numerically + as hex    (expect the fault)
  C  +-4 pages around the frame                           (is it the page or the region?)
  D  map_phys of the frame, then a user-VA copy of it     (a second path, and a
     page-table decoder that does not depend on read_phys)
  E  self-translate control: own allocation -> translate -> phys read of the
     returned PA, bytes compared                        (proves phys reads and
     translate work at all, and yields a known VA/PA pair)
  F  the two historical Apex DTB frames, for the same answer on another process

Read-only: one device handle, every mapping unmapped before exit, nothing
written outside temp\.
"""
import ctypes
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio  # noqa: E402

OUT = os.path.join(HERE, "_p74_dtbread.txt")
PAGE = 0x1000
EPROC = 0x4A3410000          # pid 19912's EPROCESS page, read OK minutes ago
DTB = 0x4A6BE3000            # ... and its DTB frame, reported unreadable
OLD = (0x57E88C000, 0x514C3E000)   # historical Apex DTB frames

kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
kernel32.VirtualAlloc.restype = ctypes.c_void_p
kernel32.VirtualAlloc.argtypes = [ctypes.c_void_p, ctypes.c_size_t,
                                  ctypes.c_uint32, ctypes.c_uint32]
kernel32.VirtualFree.argtypes = [ctypes.c_void_p, ctypes.c_size_t,
                                 ctypes.c_uint32]


def log(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")
    print(s)


def rd(g, pa, n=PAGE):
    """-> (bytes|None, errno|None)"""
    try:
        return g.read_phys(pa, n), None
    except OSError as e:
        return None, (e.args[0] if e.args else -1)


def main():
    if os.path.exists(OUT):
        os.remove(OUT)
    log("p74 dtbread")
    with gio.Gio() as g:
        log("ram_top=%#x" % (g.ram_top or 0))

        b, e = rd(g, EPROC)
        log("A control %#x ram=%s -> %s" % (EPROC, g.is_ram(EPROC),
                                            "OK" if b else "err %d %#x" % (e, e)))
        if not b:
            log("A failed -- phys read itself is broken, stop")
            return 1

        b, e = rd(g, DTB)
        log("B dtb     %#x ram=%s -> %s" % (DTB, g.is_ram(DTB),
                                            "OK" if b else "err %d %#x" % (e, e)))
        for k in (-4, -3, -2, -1, 1, 2, 3, 4):
            pa = DTB + k * PAGE
            b, e = rd(g, pa)
            log("C %+#5d %#x -> %s" % (k, pa, "OK" if b else "err %d %#x" % (e, e)))

        va = None
        try:
            va = g.map_phys(DTB, PAGE)
            buf = ctypes.string_at(va, PAGE)
            bad = sum(1 for i in range(0, PAGE, 8)
                      if struct.unpack_from("<Q", buf, i)[0] & 1)
            log("D map       -> va=%#x first=%#x present_leaves=%d/512"
                % (va, struct.unpack_from("<Q", buf, 0)[0], bad))
            log("D first4=%s" % " ".join("%016x" % struct.unpack_from("<Q", buf, i)[0]
                                        for i in range(0, 32, 8)))
        except OSError as ex:
            log("D map       -> err %s" % (ex,))
        finally:
            if va:
                try:
                    g.unmap(va, PAGE)
                    log("D unmap ok")
                except OSError as ex:
                    log("D unmap err %s" % (ex,))

        buf2 = kernel32.VirtualAlloc(None, PAGE, 0x1000 | 0x2000, 0x04)
        try:
            ctypes.memset(buf2, 0x5A, PAGE)
            ok, pa = g.translate(buf2)
            log("E translate va=%#x -> %s" % (buf2, ("pa=%#x" % pa) if ok else ("err %s" % pa)))
            if ok:
                b, e = rd(g, pa & ~0xFFF)
                same = b is not None and b[pa & 0xFFF] == 0x5A
                log("E readpa    %#x -> %s marker=%s"
                    % (pa & ~0xFFF, "OK" if b else "err %d %#x" % (e, e), same))
        finally:
            kernel32.VirtualFree(buf2, 0, 0x8000)

        for pa in OLD:
            b, e = rd(g, pa)
            log("F old dtb %#x ram=%s -> %s" % (pa, g.is_ram(pa),
                                               "OK" if b else "err %d %#x" % (e, e)))
    log("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
