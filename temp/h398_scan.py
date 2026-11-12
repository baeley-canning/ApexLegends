r"""h398 -- current EPROCESS lookup with fixed MapK physical read.
Small scan using one-page Read calls; selection uses Proc tag + confirmed
EPROCESS type/name/PID. If none, prints every candidate's raw object fields.
No claimed success without PEB->complete-Apex-PE parse.
"""
import ctypes as C
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

PID = 14624
NSCAN = 1 << 28
OUT = os.path.join(ROOT, "temp", "h398_scan.txt")

def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")

open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
g = gio.Gio(chunk=0x1000)
mr = qk_gdrv_mapread.install(g)
say("H398 pid=%d time=%s ranges=%s" % (PID, time.strftime("%F %T"), mr.note))
g.read_phys = mr.read
try:
    dl.NAME = b"r5apex_dx12.ex\0"
    count = 0
    for lo, hi in mr.ranges:
        pos = lo
        while pos + 0x1000 <= hi:
            count += 1
            if count % 200000 == 0:
                say("page %d pa=%#x" % (count, pos))
            try:
                blk = g.read_phys(pos, 0x1000)
            except OSError:
                pos += 0x1000
                continue
            at = blk.find(b"Proc\0")
            if at >= 0:
                for base_candidate in (at + 8, at + 0xC, at + 0x10):
                    for noff, toff, doff, poff in ((0x338, 0, 0x28, 0x1D0),
                                                   (0x3A8, 0x70, 0x98, 0x240)):
                        if base_candidate + noff + 0xF >= 0x1000:
                            continue
                        if blk[base_candidate+noff:base_candidate+noff+15] != dl.NAME:
                            continue
                        header = blk[base_candidate:base_candidate+0x400]
                        say("PROC obj=%#x off=%#x type=%d type70=%d pid1d0=%d pid240=%d dtb28=%#x dtb98=%#x" %
                            (pos + base_candidate, noff, header[toff], header[0x70],
                             struct.unpack_from("<I", header, 0x1D0)[0],
                             struct.unpack_from("<I", header, 0x240)[0],
                             struct.unpack_from("<Q", header, 0x28)[0],
                             struct.unpack_from("<Q", header, 0x98)[0]))
                        if header[toff] == 3 and struct.unpack_from("<I", header, poff)[0] == PID:
                            dtb = struct.unpack_from("<Q", header, doff)[0] & dl.MASK
                            if not mr.in_ram(dtb, 0x1000):
                                continue
                            rd = qk_va.Reader(g, dtb)
                            raw = rd.read(qk_va._peb_va(PID) + 0x10, 8)
                            if not raw:
                                continue
                            b = struct.unpack("<Q", raw)[0]
                            meta = dl.validate_pe(rd.read(b, 0x1000))
                            say("PE dtb=%#x base=%#x meta=%s" % (dtb, b, meta))
                            if meta and meta["size"] == 0xDFB8000:
                                qk_va.save_cache(PID, dtb, b)
                                say("VERDICT: PASS -- first valid in-match read bridge")
                                sys.exit(0)
            pos += 0x1000
    say("VERDICT: BLOCKED -- no valid EPROCESS/PE from full bounded scan")
except Exception:
    import traceback
    say(traceback.format_exc())
finally:
    g.close()