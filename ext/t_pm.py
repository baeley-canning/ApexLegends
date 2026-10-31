r"""t_pm.py -- \Device\PhysicalMemory access matrix + map/write test (run as SYSTEM)."""
import ctypes
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio        # noqa: E402
import physmem    # noqa: E402

OUT = os.path.join(HERE, "out_pm.txt")
LOG = []


def log(s):
    LOG.append(s)
    print(s)


def elevated_main():
    g = gio.Gio()
    ntdll = physmem.ntdll
    masks = [0xF001F, 0x6, 0x4, 0x2, 0x1, 0x8, 0x10, 0x20000]
    for m in masks:
        pm = None
        try:
            pm = physmem.PhysMem.__new__(physmem.PhysMem)
            pm.views = {}
            pm.h = None
            u, buf = physmem._us(r"\Device\PhysicalMemory")
            oa = physmem.OBJECT_ATTRIBUTES()
            oa.Length = ctypes.sizeof(oa)
            oa.ObjectName = ctypes.pointer(u)
            oa.Attributes = 0x200
            h = ctypes.c_void_p(0)
            st = ntdll.NtOpenSection(ctypes.byref(h), m, ctypes.byref(oa))
            log("mask=%#07x -> %#08x handle=%s" % (m, st & 0xFFFFFFFF, bool(h.value)))
            if st >= 0 and h.value:
                pm.h = h
                data = pm.read(0x1000, 0x40)
                gdrv = g.read_phys(0x1000, 0x40)
                log("  map+read ok; matches gdrv=%s; first=%s"
                    % (data == gdrv, data[:8].hex()))
                orig = pm.read(0x1010, 8)
                pm.write(0x1010, struct.pack("<Q", 0x1D0A5E1A1C0FFEE0))
                back = g.read_phys(0x1010, 8)
                pm.write(0x1010, orig)
                log("  write coherent=%s restored=%s"
                    % (back == struct.pack("<Q", 0x1D0A5E1A1C0FFEE0),
                       g.read_phys(0x1010, 8) == orig))
                pm.close()
                log("VERDICT: PHYSMEM %s WORKS" % ("0x%x" % m))
                break
        except Exception as e:
            log("mask=%#07x exception %s" % (m, e))
            if pm and pm.h:
                pm.close()
    g.close()
    open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
    return 0


def main():
    if "--elevated" in sys.argv:
        return elevated_main()
    print("run via run_task.ps1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
