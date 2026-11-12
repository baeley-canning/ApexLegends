r"""h401: use the actually finished fresh-hit evidence, MapK reads.
17 hits, printed fields from current EPROCESS layout (only +0x338 discriminates
a real object), link/PID read-back, then DTB -> full Apex PE.  Name copies
must be re-read on capture, unlike earlier time-separated stale hits.
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

OUT = os.path.join(ROOT, "temp", "h401_flat_objects.txt")

def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")

open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
say("H401 finished-scan objects %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
pid = qk_bridge_pid = qk_bridge.find_pid()[0] if False else 14624
say("target_pid=%d" % pid)
g = gio.Gio(chunk=0x1000)
mr = qk_gdrv_mapread.install(g)
say("MapK enabled ranges=%s" % mr.note)
# Same-name fresh scan just completed on MapK; its 17 hits are collected as a
# probe output, not future config. To consume them safely, parse dl.name_hits's
# fresh checkpoint so offsets are not made up from old PID runs.
proc_log = os.path.join(ROOT, "_ritual", "p40d_progress.txt")
hits = []
with open(proc_log, errors="ignore") as f:
    for ln in f:
        if ln.startswith("HIT ") or (len(ln.split()) > 1 and ln.split()[1] == "HIT"):
            hits.append(int(ln.split()[2].split("pa=", 1)[1], 0) if ln[0].isdigit()
                        else int(ln.split()[1], 0))
say("FRESH HITS=%s" % [hex(h) for h in hits[:24]])
try:
    for hit in hits:
        try:
            blob = mr.read(hit - 0x338, 0x700)
        except OSError as e:
            say("hit=%#x read_err=%s" % (hit, e))
            continue
        name = blob[0x338:0x338+15]
        typ = blob[0] if blob else -1
        pval = struct.unpack_from("<I", blob, 0x1D0)[0]
        dtb = struct.unpack_from("<Q", blob, 0x28)[0]
        flink = struct.unpack_from("<Q", blob, 0x1D8)[0]
        blink = struct.unpack_from("<Q", blob, 0x1E0)[0]
        say("obj=%#x type=%d pid=%d name=%r dtb=%#x links=%#x/%#x" %
            (hit-0x338, typ, pval, name, dtb, flink, blink))
        if name != b"r5apex_dx12.ex\0" or typ != 3 or pval != pid:
            continue
        if not mr.in_ram(dtb & dl.MASK, 0x1000):
            continue
        say("VALID_PROCESS obj=%#x dtb=%#x" % (hit-0x338, dtb))
        rd = qk_va.Reader(g, dtb)
        peb = qk_va._peb_va(pid)
        raw = rd.read(peb+0x10, 8)
        if not raw:
            say("PEB_NO_READ %s" % dl.probe_dtb(g, dtb))
            continue
        base = struct.unpack("<Q", raw)[0]
        page = rd.read(base, 0x1000)
        meta = dl.validate_pe(page) if page else None
        say("RESULT: dtb=%#x base=%#x PE=%s" % (dtb, base, meta))
        if meta and meta["size"] == 0xDFB8000:
            qk_va.save_cache(pid, dtb, base)
            say("VERDICT: PASS - valid in-match game bridge")
            sys.exit(0)
    say("VERDICT: BLOCKED - no matching PID/name among fresh hits")
except Exception:
    import traceback
    say(traceback.format_exc())
finally:
    g.close()