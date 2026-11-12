r"""h395: existing gdrv3 ONLY. A bounded structural EPROCESS reader.
Why: earlier probes only decoded 0x338/0x3A8 and overconstrained the alternate
layout; qk_va's validated search includes name offsets through 0x5B0. Read the
small region around known current hits once, enumerate names, type, live pid,
DTB layout candidates, then prove any desirable candidate by PEB->base->PE.
No new service/driver/writes and no arbitrary full-physical sweep (R10).
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

PID = 14008
NAME = b"r5apex_dx12.ex\0"
HITS = [0x1860DA5E0, 0x1DB967920, 0x2D87FB490, 0x370C7BFF2,
        0x385F57E0B, 0x63DFF3FF2, 0x2D5C61E0B]
OUT = os.path.join(ROOT, "temp", "h395_gdrv_object.txt")
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
say("H395 bounded EPROCESS recognition: %s, %d ranges" % (note, len(ranges)))
cache = {}
def page(pa):
    pa &= ~0xFFF
    if pa not in cache:
        try:
            cache[pa] = dl.retry_phys(g, pa, 0x1000, tries=5)
        except OSError as ex:
            cache[pa] = None
    return cache[pa]

def read(pa, n):
    if not g.is_ram(pa):
        return None
    buf = page(pa)
    if not buf:
        return None
    off = pa & 0xFFF
    if off + n > 0x1000:
        return None
    return buf[off:off+n]

candidates = []
try:
    for hit in HITS:
        for noff in qk_va.NAME_OFFS:
            obj = hit - noff
            if read(obj + noff, 15) != NAME:
                continue
            raw = read(obj, 0x600)
            if raw:
                pid_hits = []
                for i in range(0x100, 0x600 - 8, 4):
                    if struct.unpack_from("<Q", raw, i)[0] == PID:
                        pid_hits.append(i)
                for typoff, dtboff in ((0, 0x28), (0x70, 0x98), (0x74, 0xA8)):
                    dtb = struct.unpack_from("<Q", raw, dtboff)[0]
                    say("MATCH hit=%#x nameoff=%#x obj=%#x typeoff=%#x type=%d pidoffs=%s dtboff=%#x dtb=%#x proc=%s" %
                        (hit, noff, obj, typoff, raw[typoff],
                         [hex(x) for x in pid_hits], dtboff, dtb, read(obj-0xC, 4)))
                    if raw[typoff] == 3 and pid_hits and 0x1000 <= dtb < g.ram_top and not (dtb & 0xFFF):
                        pid_offsets = [x for x in pid_hits if struct.unpack_from("<I", raw, x)[0] == PID]
                        if pid_offsets:
                            candidates.append((obj, dtb, typoff, noff))
    # compact unique, no arbitrary qword frame chosen
    uniq = {dtb: (obj, dtb, toff, noff) for obj, dtb, toff, noff in candidates}
    say("VALIDATED_PID_DTBS=%d" % len(uniq))
    if not uniq:
        # Narrow fallback: use the repo's own offset-agnostic candidate decoder,
        # which does NOT assume an EPROCESS major version header location either.
        for hit in HITS:
            for addr, dtb, d in qk_va._candidate_dtbs(g, hit, qk_va.Ram(ranges)):
                raw = read(addr - 0x28, 0x800)
                if not raw:
                    continue
                whole = d + 0x28
                for po in range(0x180, whole - 8, 4):
                    if struct.unpack_from("<I", raw, po)[0] == PID:
                        uniq[dtb] = (hit - d, dtb, 0, d)
        say("after qkva_shape_search=%d" % len(uniq))
    peb = qk_va._peb_va(PID)
    say("PEB=%#x" % (peb or 0))
    for obj, dtb, toff, noff in uniq.values():
        say("TRY dtb=%#x obj=%#x" % (dtb, obj))
        try:
            rd = qk_va.Reader(g, dtb)
            raw = rd.read(peb + 0x10, 8)
            if not raw:
                say("PEB_READ_FAIL %s" % dl.probe_dtb(g, dtb))
                continue
            base = struct.unpack("<Q", raw)[0]
            page_bytes = rd.read(base, 0x1000)
            meta = dl.validate_pe(page_bytes) if page_bytes else None
            say("BASE=%#x PE=%s image_pa=%s" % (base, meta, rd.page_pa(base)))
            if meta and meta["size"] == 0xDFB8000:
                say("RESULT: dtb=%#x base=%#x image_pa=%#x PASS" %
                    (dtb, base, rd.page_pa(base)))
                qk_va.save_cache(PID, dtb, base)
                say("VERDICT: PASS - physical reads resolve Apex virtual addresses")
                sys.exit(0)
        except OSError as e:
            say("walk_error=%s" % e)
    say("RESULT: objects recognized=%d, zero PEB->PE proofs" % len(uniq))
    say("VERDICT: BLOCKED - no candidate walk unlocked")
finally:
    g.close()