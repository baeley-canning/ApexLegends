r"""p76_retry.py -- two workarounds for a frame the read path refuses.

p74/p75: 0x4a6be3000 (pid 19912 PML4) faults 1450 at every size, every offset,
three tries, while all eight neighbours read; map_phys fails too.  But
0x57e88c000 faulted in an earlier run and reads now, so blindness is per page
AND per time -- not a property of page tables.

Parts:
  A  mapK (0xC3502019) on the control page               (mechanism baseline)
  B  mapK on the failing page                            (other mechanism?)
  C  kalloc + mapK into it, read the landing buffer      (does mapK deliver bytes?)
  D  patient retry: 8-byte read up to 120 x 1 s          (is blindness transient,
     and if it lifts, do the bytes look like a PML4?)

mapK/kalloc are the only state changes; every allocation is freed and every
mapping unmapped in finally blocks.
"""
import ctypes
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio  # noqa: E402

OUT = os.path.join(HERE, "_p76_retry.txt")
BAD = 0x4A6BE3000
CTL = 0x4A3410000
PAGE = 0x1000
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)


def log(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")
    print(s)


def main():
    if os.path.exists(OUT):
        os.remove(OUT)
    log("p76 retry")
    with gio.Gio() as g:
        for tag, pa in (("A", CTL), ("B", BAD)):
            ok, err, kva = g.map_kernel(pa, PAGE, 0)
            log("%s mapK %#x -> ok=%s err=%s kva=%s"
                % (tag, pa, ok, err, ("%#x" % kva) if kva else "-"))

        ok, err, pair = g.kernel_alloc(PAGE)
        log("C kalloc -> ok=%s err=%s pair=%s"
            % (ok, err, ("%#x/%#x" % pair) if pair else "-"))
        try:
            if ok:
                va, pa_alloc = pair
                ok2, err2, kva2 = g.map_kernel(BAD, PAGE, va)
                log("C mapK into alloc -> ok=%s err=%s kva=%s"
                    % (ok2, err2, ("%#x" % kva2) if kva2 else "-"))
                if ok2:
                    buf = ctypes.string_at(va, 32)
                    log("C landing %s" % " ".join(
                        "%016x" % struct.unpack_from("<Q", buf, i)[0]
                        for i in range(0, 32, 8)))
        finally:
            if ok:
                log("C kfree -> %s" % (g.kernel_free(pair[0], pair[1])[1],))

        t0 = time.perf_counter()
        got = None
        for i in range(120):
            try:
                b = g.read_phys(BAD, 8)
                got = (i + 1, b)
                break
            except OSError:
                time.sleep(1.0)
        if got:
            n, b = got
            log("D retry lifted after %d s (try %d) first=%016x"
                % (int(time.perf_counter() - t0), n, struct.unpack("<Q", b)[0]))
            pm = g.read_phys(BAD, PAGE)
            pres = sum(1 for i in range(0, PAGE, 8)
                       if struct.unpack_from("<Q", pm, i)[0] & 1)
            kern = sum(1 for i in range(0x100, 0x200) * 8 if True
                       for _ in [0] if True)
            kern = sum(1 for i in range(0x100, 0x200) * 8 if True
                       for _ in [0] if True)
            kpres = 0
            for i in range(0x100 * 8, 0x200 * 8, 8):
                if struct.unpack_from("<Q", pm, i)[0] & 1:
                    kpres += 1
            log("D page reads now: present=%d/512 kernel-present=%d/256" % (pres, kpres))
            log("D first4=%s" % " ".join("%016x" % struct.unpack_from("<Q", pm, i)[0]
                                         for i in range(0, 32, 8)))
        else:
            log("D retry never lifted in %d s" % int(time.perf_counter() - t0))
    log("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
