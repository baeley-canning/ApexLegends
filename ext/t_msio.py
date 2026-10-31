r"""t_msio.py -- probe MsIo64 0x80102040 map / 0x80102044 unmap with RAM targets."""
import ctypes
import os
import struct
import sys
import time
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

OUT = os.path.join(HERE, "out_msio.txt")
LOG = []


def log(s):
    LOG.append(s)
    print(s)


MAP_IOCTL = 0x80102040
UNMAP_IOCTL = 0x80102044


def ioctl(h, code, inb, out_len):
    ib = ctypes.create_string_buffer(inb, len(inb))
    ob = ctypes.create_string_buffer(max(out_len, 1))
    got = wintypes.DWORD(0)
    ok = gio.kernel32.DeviceIoControl(h, code, ib, len(inb), ob, out_len,
                                      ctypes.byref(got), None)
    return ok, ctypes.get_last_error(), ob.raw[:got.value], got.value


def elevated_main():
    verdicts = []
    g = gio.Gio()
    ref = g.read_phys(0x1000, 0x10)
    log("gdrv ref @0x1000: %s" % ref.hex(" "))

    h = gio.kernel32.CreateFileW(r"\\.\MSIO", gio.GENERIC_READ | gio.GENERIC_WRITE,
                                 0, None, gio.OPEN_EXISTING, 0, None)
    if not h or h == gio.INVALID_HANDLE:
        log("open \\\\.\\MSIO failed err=%d" % ctypes.get_last_error())
        open(OUT, "w").write("\n".join(LOG) + "\n")
        return 1
    log("opened \\\\.\\MSIO handle=%#x" % h)

    # map probes: try (size=4, phys=0x1000) then (size=0x1000, phys=0x1000)
    mapped = None
    for size, phys in [(4, 0x1000), (0x1000, 0x1000), (4, 0x2000), (4, 0x100000)]:
        ib = struct.pack("<QQQQQ", size, phys, 0, 0, 0)
        ok, err, ob, info = ioctl(h, MAP_IOCTL, ib, 0x28)
        vals = struct.unpack("<QQQQQ", ob[:0x28]) if len(ob) >= 0x28 else ()
        log("map size=%#x phys=%#x -> ok=%s err=%d info=%d out=%s"
            % (size, phys, ok, err, info,
               " ".join("%#x" % v for v in vals) if vals else "-"))
        if ok and len(vals) == 5 and vals[3]:
            mapped = (vals, phys, size)
            sample = ctypes.string_at(vals[3], min(size, 0x10))
            log("   bytes at VA %#x: %s" % (vals[3], sample.hex(" ")))
            log("   matches gdrv=%s" % (sample == ref[:len(sample)]))
            break
    if mapped:
        vals, phys, size = mapped
        va = vals[3]
        # write test through the MsIo mapping
        orig = ctypes.string_at(va, 8)
        marker = struct.pack("<Q", 0x0DEFACED0FF1CE0)
        ctypes.memmove(va, marker, 8)
        back = g.read_phys(phys, 8)
        ctypes.memmove(va, orig, 8)
        restored = g.read_phys(phys, 8)
        log("write via MsIo mapping: orig=%s back=%s restored=%s"
            % (orig.hex(), back.hex(), restored.hex()))
        verdicts.append(("MsIo write coherent", back == marker and restored == orig))
        # unmap
        ib2 = struct.pack("<QQQQQ", vals[0], vals[1], vals[2], vals[3], vals[4])
        ok2, err2, _, _ = ioctl(h, UNMAP_IOCTL, ib2, 0x28)
        log("unmap ok=%s err=%d" % (ok2, err2))
    else:
        verdicts.append(("MsIo map", False))

    gio.kernel32.CloseHandle(h)
    g.close()
    log("")
    log("=== VERDICTS ===")
    for n, r in verdicts:
        log("  %-22s %s" % (n, {True: "PASS", False: "FAIL"}.get(r, "n/a")))
    open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
    return 0


def main():
    if "--elevated" in sys.argv:
        return elevated_main()
    print("run via run_task.ps1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
