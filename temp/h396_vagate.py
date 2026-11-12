r"""h396 -- use MapK reads (0xC3502019, proven live frames) to satisfy the
original DTB->PEB->Apex PE gate.  No alternative/custom driver is loaded,
no writes, no sweeping full physical RAM, no excuse without byte read-back.

Poor man's inventory: query-only PEB; name tags near today's cached hits and
the whole EPROCESS shape from measured local recipes; primary DTB+0x28 and
alternative +0x98 are validated with live PID before any table operations.
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

OUT = os.path.join(ROOT, "temp", "h396_vagate.txt")
PID = 14008
PEB = 0x24B000
HITS = [0x1860DA5E0, 0x1DB967920, 0x2D87FB490, 0x370C7BFF2,
        0x385F57E0B, 0x63DFF3FF2, 0x2D5C61E0B]


def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")


open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
say("=== h396 gdrv3 MapK virtual read gate %s ===" %
    time.strftime("%Y-%m-%d %H:%M:%S"))
g = gio.Gio(chunk=0x1000)
try:
    mr = qk_gdrv_mapread.install(g)
    say("MapK installed ranges=%s" % mr.note)
    for pa in (0x5732E3000, 0x33BCB0000):
        p = mr.read(pa, 512)
        present = sum(1 for v in struct.unpack("<64Q", p) if v & 1)
        say("old_1450_frame=%#x now_reads 512 bytes present_entries=%d first=%#x" %
            (pa, present, struct.unpack_from("<Q", p, 0)[0]))
    cache = {}
    def read(pa, n):
        result = bytearray()
        for cur in range(pa, pa + n, 0x1000):
            size = min(pa + n - cur, 0x1000)
            if cur not in cache:
                cache[cur] = mr.read(cur, 0x1000)
            result += cache[cur][:size]
        return bytes(result)

    found = []
    for hit in HITS:
        for noff in qk_va.NAME_OFFS:
            if read(hit - noff + noff, 15) != b"r5apex_dx12.ex\0":
                continue
            obj = hit - noff
            raw = read(obj, 0x640)
            pids = [i for i in range(0x100, 0x600-8, 4)
                    if struct.unpack_from("<I", raw, i)[0] == PID]
            for typoff, dtboff in ((0, 0x28), (0x70, 0x98)):
                if raw[typoff] != 3:
                    continue
                dtb = struct.unpack_from("<Q", raw, dtboff)[0] & dl.MASK
                say("EPROCESS obj=%#x nameoff=%#x pidoffs=%s type=%d dtboff=%#x dtb=%#x" %
                    (obj, noff, pids, typoff, dtboff, dtb))
                pid_confirmation = next((i for i in pids
                                        if struct.unpack_from("<Q", raw, i)[0] == PID), None)
                if not pids or pid_confirmation is None or not dtb or not mr.in_ram(dtb, 0x1000):
                    continue
                found.append((obj, dtb, noff, pid_confirmation))
    seen = set()
    for obj, dtb, noff, poff in found:
        if dtb in seen:
            continue
        seen.add(dtb)
        say("TRY DTB=%#x obj=%#x confirmed_pidoff=%#x" % (dtb, obj, poff))
        rd = qk_va.Reader(g, dtb)
        raw = rd.read(PEB + 0x10, 8)
        if not raw:
            say("walk fails: %s" % dl.probe_dtb(g, dtb))
            continue
        base = struct.unpack("<Q", raw)[0]
        page = rd.read(base, 0x1000)
        meta = dl.validate_pe(page) if page else None
        say("IMAGE base=%#x pa=%s meta=%s" % (base, rd.page_pa(base), meta))
        if meta and meta["size"] == 0xDFB8000:
            qk_va.save_cache(PID, dtb, base)
            say("RESULT: DTB=%#x image_va=%#x image_pa=%#x MapK=True" %
                (dtb, base, rd.page_pa(base)))
            say("VERDICT: PASS - gdrv3 MapK translation proves Apex PE")
            sys.exit(0)
    say("RESULT: no validated PEB->PE object among %d candidates" % len(found))
    # Proc-tag locator still uses the repository-established candidate recipe
    # but all reads now go through MapK, not the known-bad physical-copy route.
    import importlib.util
    spec = importlib.util.spec_from_file_location("h142", os.path.join(ROOT, "temp", "_p142.py"))
    h = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(h)
    h.OUT = os.path.join(ROOT, "temp", "h396_proctag.txt")
    h._f = open(h.OUT, "w")
    dtb, _seeds = h.find_dtb(g, PID, budget=55.0, seeds=[], proctag=True)
    say("ESTABLISHED_PROC_DTBS=%s" % (hex(dtb) if dtb else "none"))
    if dtb:
        rd = qk_va.Reader(g, dtb)
        raw = rd.read(PEB + 0x10, 8)
        if raw:
            base = struct.unpack("<Q", raw)[0]
            page = rd.read(base, 0x1000)
            meta = dl.validate_pe(page) if page else None
            say("BASE=%#x PE=%s" % (base, meta))
            if meta and meta["size"] == 0xDFB8000:
                qk_va.save_cache(PID, dtb, base)
                say("RESULT: dtb=%#x base=%#x MapK True" % (dtb, base))
                say("VERDICT: PASS - final read gate")
                sys.exit(0)
    say("VERDICT: BLOCKED - transport fixed; object/table discovery remains")
except Exception:
    import traceback
    say(traceback.format_exc())
    say("VERDICT: FAIL - do not claim carrier transport unavailable")
finally:
    g.close()