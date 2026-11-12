r"""h392 -- translation gate for the provider-shaped external. Read-only, gdrv3.

PRE: PID + PEB from the normal process-query bridge (no RPM), cached name hits.
DTB: EPROCESS+0x28, ONLY after ImageFileName, live PID, and layout agree.
PASS: DTB reads AND PEB.ImageBaseAddress resolves AND a complete Apex PE header
      reads through gdrv3, with the expected machine and SizeOfImage.
FAIL/BLOCKED: record exactly which of those steps has no successful read-back.
No arbitrary-frame guessing, no driver/service/CI changes, no process writes.
Output: temp/_h392_stage0.txt (rerun with --new for a fresh evidence file).
"""
import os
import re
import struct
import subprocess
import sys
import time
import math

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio
import dumplive as dl
import qk_va

IMAGE_SIZE = 0xDFB8000
BRIDGE = os.path.join(ROOT, "QwenKernPremium", "build", "qk_stage0_bridge.exe")


def option(name, default=None):
    for a in sys.argv[1:]:
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
    return default


def say(line):
    print(line, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(line + "\n")


def live_pid(want):
    try:
        dl.find_pid()
        return want
    except OSError:
        return None


def peb_of(pid):
    if not os.path.isfile(BRIDGE):
        raise RuntimeError("missing qk_stage0_bridge.exe; build it first")
    p = subprocess.run([BRIDGE, "--pid", str(pid)], capture_output=True,
                       text=True, timeout=20)
    say("bridge_stdout: " + p.stdout.strip().replace("\n", " | "))
    m = re.search(r"RESULT: pid=(\d+) peb=0x([0-9A-Fa-f]+)", p.stdout)
    if p.returncode != 0 or not m:
        raise RuntimeError("PEB query failed: rc=%d stderr=%s" %
                           (p.returncode, p.stderr.strip()))
    return int(m.group(2), 16)


def latest_hits(pid):
    p = os.path.join(HERE, "qk_hits_%d.txt" % pid)
    try:
        with open(p, encoding="ascii") as f:
            hits = [int(s, 16) for s in f.read().split()]
        say("name_hits_cache=%s hits=%d mtime=%s" %
            (p, len(hits), time.strftime("%Y-%m-%d %H:%M:%S",
                                        time.localtime(os.path.getmtime(p)))))
        return hits
    except (OSError, ValueError) as e:
        say("name_hits_unavailable=%s" % e)
        return []


def eprocess(g, pid, hit):
    """Return (object_pa, dtb) only when two layouts match the live PID."""
    lo = (hit - 0x480) & ~0xFFF
    hi = hit + 0x20
    data = bytearray()
    for pa in range(lo, hi, 0x1000):
        if not g.is_ram(pa):
            say("ram_guard_refused read=%#x" % pa)
            return None
        data += dl.retry_phys(g, pa, 0x1000, tries=3)
    for off in (0x338, 0x3A8):
        b = hit - lo - off
        if b < 0 or b + 0x500 > len(data):
            continue
        if data[b + off:b + off + 15] != b"r5apex_dx12.ex\0":
            continue
        dtype = struct.unpack_from("<Q", data, b + 0x28)[0]
        alt_dtype = struct.unpack_from("<Q", data, b + 0x98)[0]
        pairs = []
        for i in range(0x1A0, min(0x500, len(data) - b - 8), 4):
            if struct.unpack_from("<I", data, b + i)[0] == pid:
                pairs.append(i)
        if (data[b] == 3 and 0x1D0 in pairs and
                data[b + 0x347] == 2 and 0 < dtype < g.ram_top):
            return {"obj": hit - off, "dtb": dtype & dl.MASK,
                    "pid_off": 0x1D0, "type": 3, "layout": "338/28"}
        if (off == 0x3A8 and data[b + 0x70] == 3 and 0x240 in pairs and
                0 < alt_dtype < g.ram_top and data[b + 0x20] == 0x80):
            return {"obj": hit - off, "dtb": alt_dtype & dl.MASK,
                    "pid_off": 0x240, "type": 3, "layout": "3a8/98"}
    say("hit=%#x no live-pid EPROCESS match" % hit)
    return None


def translate(w, va, stages):
    """Explicit PML4/PDPT/PD/PT walk. A None at every stage is a BLOCK."""
    result = []
    for level, shift, pa in (("PML4", 39, w.cr3), ("PDPT", 30, None),
                             ("PD", 21, None), ("PT", 12, None)):
        index = (va >> shift) & 0x1FF
        buf = (w.pml4 if level == "PML4" else w.cache.get(pa))
        if buf is None:
            stages.append("%s@PA=%#x READ_FAILED_OR_NOT_CACHED" % (level, pa or 0))
            return None
        entry = struct.unpack_from("<Q", buf, index * 8)[0]
        result.append((level, pa if level != "PML4" else w.cr3, entry))
        if not w.g.is_ram(pa):
            stages.append("%s[%d] RAM_GUARD entry=%#x" % (level, index, entry))
            return None
        pa = entry & dl.MASK
        if not g.is_ram(pa):
            stages.append("%s[%d] RAM_GUARD entry=%#x" % (level, index, entry))
            return None
    pte = result[-1][2]
    if pte & 0x80:
        stages.append("LARGE_PAGE_NOT_HANDLED")
        return None
    for level, pa, entry in result:
        say("translate %s table_pa=%#x entry=%#x" % (level, pa, entry))
    return pte & dl.MASK


def válidate_image(w, peb_va):
    raw = w.read(peb_va + 0x10, 8)
    if not raw:
        return None, "PEB_IMAGE_BASE_READ_FAILED"
    base = struct.unpack("<Q", raw)[0]
    page = w.read(base, 0x1000)
    if not page:
        return None, "IMAGE_PAGE_READ_FAILED base=%#x" % base
    meta = dl.validate_pe(page)
    if not meta or meta["size"] != IMAGE_SIZE:
        return None, "PE_MISMATCH size=%s base=%#x" % (
            meta["size"] if meta else "none", base)
    return (base, struct.unpack_from("<I", page, 0x88)[0], meta), None


OUT = os.path.join(HERE, "_h392_stage0.txt")
if "--new" in sys.argv:
    n = 2
    while os.path.exists(os.path.join(HERE, "_h392_stage0_v%d.txt" % n)):
        n += 1
    OUT = os.path.join(HERE, "_h392_stage0_v%d.txt" % n)
open(OUT, "w", encoding="ascii").close()
pid = int(option("pid", "14008"), 0)
say("=== h392 read-only DTB->VA->phys PE gate ===")
say("time=%s pid=%d" % (time.strftime("%Y-%m-%d %H:%M:%S"), pid))
g = None
try:
    if live_pid(pid) is None:
        say("RESULT: game_not_running")
        say("VERDICT: SKIPPED - no live-game verdict")
        sys.exit(2)
    if option("no-elevate") is None and not dl.elevation():
        say(dl.run_elevated('"%s" %s --no-elevate' %
                           (os.path.abspath(__file__), " ".join(sys.argv[1:]))))
        sys.exit(0)
    peb = peb_of(pid)
    say("PEB=%#x" % peb)
    dl.PROG = os.path.join(HERE, "_h392_progress_v2.txt")
    g = gio.Gio(chunk=0x1000)
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    ram = qk_va.Ram(ranges)
    g.is_ram = ram.page_ok
    say("gdrv3_opened ram_top=%#x ranges=%d note=%s" %
        (g.ram_top, len(ranges), note))
    # Seconds if today's name-hit cache still yields the matching process;
    # a fresh sweep is bounded, and every read remains in the actual RAM map.
    hits = latest_hits(pid)
    if "--fresh" in sys.argv or not hits:
        say("name_hit_scan=fresh (no cache for this live PID)")
        hits, skipped, chunks, rescued = dl.name_hits(g, ranges)
        say("name_hits=%d skipped=%d chunks=%d rescued=%d" %
            (len(hits), skipped, chunks, rescued))
    objects = []
    for hit in hits:
        try:
            e = eprocess(g, pid, hit)
        except OSError as ex:
            say("hit=%#x eprocess_read_err=%s" % (hit, ex))
            continue
        if e and e["obj"] not in [x["obj"] for x in objects]:
            objects.append(e)
            say("EPROCESS candidate obj=%#x dtb=%#x pid_off=%#x layout=%s" %
                (e["obj"], e["dtb"], e["pid_off"], e["layout"]))
    say("RESULT: live_pid_dtb_candidates=%d" % len(objects))
    if not objects:
        say("RESULT: BLOCKED_NO_LIVE_DTB")
        say("VERDICT: BLOCKED - no PID-validated DTB; no translation claimed")
        sys.exit(3)
    fail_reasons = []
    for e in objects[:8]:
        dtb = e["dtb"]
        frame_ok = False
        for attempt in range(8):
            try:
                g.read_phys(dtb, 0x1000)
                frame_ok = True
                break
            except OSError as ex:
                err = ex
        if not frame_ok:
            fail_reasons.append("PML4_read=%s" % err)
            say("dtb=%#x BLOCKED_PML4_READ=%s" % (dtb, err))
            continue
        say("dtb=%#x PML4_READ_OK on_try=%d" % (dtb, attempt + 1))
        w = dl.Walk(g, dtb)
        base, error = None, None
        try:
            found, why = validate_image(w, peb)
        except Exception as ex:                    # precise diagnostics below
            found, why = None, "%s: %s" % (type(ex).__name__, ex)
        if not found:
            fail_reasons.append(why)
            say("dtb=%#x VALIDATION_FAILED=%s why=%s" %
                (dtb, why, dl.probe_dtb(g, dtb)))
            continue
        base, stamp, meta = found
        image_pa = w.page_pa(base)
        say("PE_VALIDATED base=%#x image_pa=%#x size=%#x stamp=%#x sections=%d" %
            (base, image_pa, meta["size"], stamp, len(meta["secs"])))
        # Second read on a fresh Reader proves this is not one stale cached page.
        again = qk_va.Reader(g, dtb).read(base, 2)
        if again != b"MZ" or live_pid(pid) is None:
            say("RESULT: second_readback_or_alive_failed")
            say("VERDICT: FAIL - do not use this DTB")
            sys.exit(4)
        qk_va.save_cache(pid, dtb, base)
        say("game_alive_at_end=True")
        say("RESULT: image_pa=%#x dtb=%#x translated_VA_to_PA=True" %
            (image_pa, dtb))
        say("VERDICT: PASS - translated, validated Apex PE through gdrv3")
        sys.exit(0)
    say("RESULT: BLOCKED_TRANSLATION reasons=%s" % " ; ".join(fail_reasons))
    say("game_alive_at_end=%s" % (live_pid(pid) is not None))
    say("VERDICT: BLOCKED - PML4/VA/PE read-back missing")
    sys.exit(5)
except Exception:
    import traceback
    say("EXCEPTION: " + traceback.format_exc().replace("\n", " | "))
    say("game_alive_at_end=%s" % (live_pid(pid) is not None))
    say("VERDICT: FAIL - gate exception; no translation claimed")
    sys.exit(9)
finally:
    if g is not None:
        g.close()