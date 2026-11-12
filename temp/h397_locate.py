r"""h397 -- the ONLY locator: Proc pool tags -> accepted EPROCESS base -> DTB.

Unlike the mistaken large-copy searches, EVERY scan read and page-table read
is one 4KiB page (MapK copies 16 pages at once otherwise). No arbitrary frame
lookup for DTB candidate; game PID and both measured EPROCESS layouts are
checked within the small object itself before any multi-level walk (R10).
All addresses are physical pool data, never virtual offsets falsely treated
as physical addresses. One pass can yield PID; then exact PMS->header proves
the translation path. Nothing new to start or stop.
"""
import os
import struct
import sys
import time
import ctypes as C

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio
import dumplive as dl
import qk_va
import qk_gdrv_mapread

OUT = os.path.join(ROOT, "temp", "h397_locate.txt")
PID = 14008


def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")


open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
say("=== h397 4KiB Proc-locator MapK %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
k = C.WinDLL("kernel32", use_last_error=True)
k.VirtualAlloc.argtypes = [C.c_void_p, C.c_size_t, C.c_ulong, C.c_ulong]
k.VirtualAlloc.restype = C.c_void_p
k.VirtualLock.argtypes = [C.c_void_p, C.c_size_t]
g = gio.Gio(chunk=0x1000)
mr = qk_gdrv_mapread.install(g)
r = g.mapread
# choose a RAM map once; source data stays physical and bounded by real map
say("ranges=%s pml4table_read=4KiB" % r.note)


def read(pa, size):
    return r.read(pa, size)


g.read_phys = read
try:
    found = set()
    begin = time.time()
    count = 0
    for lo, hi in r.ranges:
        pa = lo
        while pa + 0x1000 <= hi:
            if time.time() - begin > 190:
                pa = hi
                break
            try:
                data = read(pa, 0x1000)
            except OSError:
                pa += 0x1000
                continue
            count += 1
            if count % 100000 == 0:
                say("scanned=%d pages time=%.1f pa=%#x candidates=%d" %
                    (count, time.time() - begin, pa, len(found)))
            matchoff = data.find(b"Proc\0")
            if matchoff < 0:
                pa += 0x1000
                continue
            # Proc pool tag can be at 0xC above its object. Name offsets have
            # been measured at 0x338 or 0x3A8; tag could have 8/0x10 padding.
            for cand in (matchoff + 0xC, matchoff + 0x10, matchoff + 8):
                if cand > 0x600:
                    continue
                for noff, toff, poff, doff in ((0x338, 0, 0x1D0, 0x28),
                                               (0x3A8, 0x70, 0x240, 0x98)):
                    if cand + noff + 15 > 0x1000:
                        continue
                    if data[cand + noff:cand + noff+15] != b"r5apex_dx12.ex\0":
                        continue
                    if data[cand + toff] != 3:
                        continue
                    if struct.unpack_from("<I", data, cand+poff)[0] != PID:
                        continue
                    dtb = struct.unpack_from("<Q", data, cand+doff)[0] & dl.MASK
                    if not dtb or not r.in_ram(dtb, 0x1000):
                        continue
                    found.add((dtb, pa+cand, noff, poff)
                              if False else dtb)
                    say("FOUND obj=%#x layout nameoff=%#x DTB=%#x" %
                        (pa + cand, noff, dtb))
            pa += 0x1000
    say("SCAN completion pages=%d elapsed=%.1f found=%d" %
        (count, time.time() - begin, len(found)))
    if not found:
        say("VERDICT: BLOCKED - process not located, no DTB asserted")
        sys.exit(4)
    for dtb in found:
        rd = qk_va.Reader(g, dtb)
        raw = rd.read(qk_va._peb_va(PID) + 0x10, 8)
        if not raw:
            say("walk_no_PEB dtb=%#x why=%s" % (dtb, dl.probe_dtb(g, dtb)))
            continue
        base = struct.unpack("<Q", raw)[0]
        page = rd.read(base, 0x1000)
        meta = dl.validate_pe(page) if page else None
        say("BASE=%#x PE=%s" % (base, meta))
        if meta and meta["size"] == 0xDFB8000:
            qk_va.save_cache(PID, dtb, base)
            say("RESULT: DTB=%#x base=%#x image_pa=%#x" %
                (dtb, base, rd.page_pa(base)))
            say("VERDICT: PASS - MapK + Proc found translation")
            sys.exit(0)
    say("VERDICT: BLOCKED - located but translation failed")
finally:
    r.close()
    g.close()