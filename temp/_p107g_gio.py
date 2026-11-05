r"""_p107g_gio.py -- read-path health probe.  READ-ONLY: no phys writes, no flags.

p107a: the stride-64 walk lost 2048/2048 hops across 0x0f000000..0x17000000 and
the plain one-page walk lost its very first page at 0x100000.  0x100000 is RAM by
construction (is_ram() returns True below 1 MiB only via the legacy branch, and
0x100000 is the SCAN_LO the 10:59 run read clean), so "this is all one bigger
hole" stops explaining it.  read_phys() has carried the GetLastError value since
it was written (`raise OSError(err, ...)`) and not one run has ever printed it,
so a dead device, a dead dispatch and a wrong request are still the same thing on
paper.  This probe prints the code and stops guessing:

  * CreateFileW on the device           -- does the handle still exist
  * translate() of one live user VA      -- different ioctl: is the driver body
                                            still dispatched, irrespective of
                                            MmMapIoSpace
  * read 16 B at pages readable at 10:59 -- 0x140155000 and neighbours
  * read 16 B at pages that must read    -- 0x1000 and 0x100000 (RAM, always)
  * one 64 KiB read at 0x100000          -- size != page: the 16-page scan chunk
  * ioctl stats                          -- a dead device answers in ~0 us

Read-only, so nothing to restore (R4 vacuous).  Output _p107g_out.txt, one RESULT
line per address, verdict in the last line.
"""
import os
os.environ.setdefault("GIO_DST_LAST", "1")   # same open/close discipline as p96
import ctypes
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio  # noqa: E402

OUT = os.path.join(HERE, "_p107g_out.txt")
_f = open(OUT, "w", encoding="utf-8")


def log(s):
    line = "%s  %s" % (time.strftime("%H:%M:%S"), s)
    _f.write(line + "\n")
    _f.flush()
    print(line)
    sys.stdout.flush()


# 0x1000/0x100000: RAM, must read.  0x200000: the p104 pin, on the BADPA list, so
# a fault there is *expected* and proves the error code is per-page, not global.
# 0x140155000: read clean at 10:59 (post-reboot it is the reference that decides
# which of "address" and "device" moved).
PAGES = [0x1000, 0x100000, 0x200000, 0x1000000, 0x2000000,
         0x10000000, 0x1400f000, 0x14010000, 0x14015000, 0x140155000,
         0x40000000, 0x80000000]

log("p107g read-path health probe (read-only)")
log("py=%s elevated=%s" % (sys.version.split()[0],
    ctypes.windll.shell32.IsUserAnAdmin()))

try:
    g = gio.Gio()
except OSError as e:
    log("FATAL open %s err=%s %s" % (gio.DEVICE, e.errno, e.strerror))
    log("VERDICT: DEVICE_GONE")
    _f.close()
    sys.exit(1)

log("opened %s chunk=%#x ram_top=%#x" % (gio.DEVICE, g.chunk, g.ram_top))

# translate() first: a user VA is mapped by definition, so this isolates dispatch.
buf = ctypes.create_string_buffer(16)
va = ctypes.addressof(buf)
ok, res = g.translate(va)
log("RESULT translate va=%#x -> %s" % (
    va, ("pa=%#x" % res) if ok else ("err=%s" % res)))

okc = 0
for pa in PAGES:
    t0 = time.perf_counter()
    try:
        b = g.read_phys(pa, 16)
        dt = (time.perf_counter() - t0) * 1e6
        okc += 1
        log("RESULT pa=%#010x ok %s %5.0f us" % (pa, b[:8].hex(), dt))
    except OSError as e:
        dt = (time.perf_counter() - t0) * 1e6
        log("RESULT pa=%#010x FAULT err=%s %r %5.0f us" % (
            pa, e.errno, e.strerror, dt))

# The fast path is 16 pages wide; if a page reads and a 64 KiB chunk does not,
# the failure is in size, not address.
try:
    b = g.read_phys(0x100000, 0x10000)
    log("RESULT chunk 0x100000+0x10000 ok %s" % b[:8].hex())
except OSError as e:
    log("RESULT chunk 0x100000+0x10000 FAULT err=%s %r" % (e.errno, e.strerror))

for code in sorted(g.stats):
    log("STAT " + g.stat_line(code))

n = len(PAGES)
verdict = ("OPEN_NO_READS" if okc == 0 else
           "READS_ALIVE" if okc == n else "PARTIAL")
log("%d/%d reads ok" % (okc, n))
log("VERDICT: " + verdict)
g.close()
log("CLOSED")
_f.close()
