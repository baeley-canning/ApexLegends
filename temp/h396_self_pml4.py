r"""h396 safe positive control: gdrv3 MapK, self->EPROCESS->DTB->PEB->PE.
Only the calling process and bounded RAM-level reads. No new driver, no writes.
"""
import os
import struct
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio
import dumplive as dl
import qk_va
import qk_gdrv_mapread

OUT = os.path.join(ROOT, "temp", "h396_self_pml4.txt")
def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")

open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
g = gio.Gio(chunk=0x1000)
ranges, note = dl.usable_ranges(g.ram_top, None, None)
g.is_ram = qk_va.Ram(ranges).page_ok
mr = qk_gdrv_mapread.install(g)
say("MapK self control %s" % note)
try:
    pid = os.getpid()
    peb = qk_va._peb_va(pid)
    say("SELF PID=%d PEB=%#x" % (pid, peb or 0))
    dl.NAME = b"python.exe\0"
    hits, skipped, chunks, rescued = dl.name_hits(g, mr.ranges)
    say("hits=%d skipped=%d chunks=%d rescued=%d" %
        (len(hits), skipped, chunks, rescued))
    found = set()
    for hit in hits:
        for noff in qk_va.NAME_OFFS:
            obj = hit - noff
            if not mr.in_ram(obj, 0x500):
                continue
            try:
                p = mr.read(obj & ~0xFFF, 0x1000)
            except OSError:
                continue
            rel = obj & 0xFFF
            if rel + 0x500 > 0x1000:
                continue
            buf = p[rel:rel+0x500]
            for toff, doff in ((0, 0x28), (0x70, 0x98)):
                if buf[noff:noff+15] != dl.NAME or buf[toff] != 3:
                    continue
                dtb = struct.unpack_from("<Q", buf, doff)[0] & dl.MASK
                po = [i for i in range(0x100, 0x480-8, 4)
                      if struct.unpack_from("<Q", buf, i)[0] == pid]
                if po and dtb and mr.in_ram(dtb, 0x1000):
                    say("EPROCESS obj=%#x name=%#x pidoffs=%s DTB=%#x" %
                        (obj, noff, po, dtb))
                    found.add(dtb)
    for dtb in found:
        rd = qk_va.Reader(g, dtb)
        raw = rd.read(peb + 0x10, 8)
        if not raw:
            continue
        base = struct.unpack("<Q", raw)[0]
        page = rd.read(base, 0x1000)
        meta = dl.validate_pe(page) if page else None
        say("DTB=%#x image=%#x PE=%s" % (dtb, base, meta))
        if meta:
            say("RESULT: gdrv3.MapK translated self->PEB->image successfully")
            say("VERDICT: PASS - actual virtual read gate")
            sys.exit(0)
    say("VERDICT: BLOCKED - no validated self EPROCESS")
except Exception:
    import traceback
    say(traceback.format_exc())
    say("VERDICT: FAIL - see exception")
finally:
    g.close()