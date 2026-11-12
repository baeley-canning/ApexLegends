r"""h393 -- one variable: decode ALL current name hits with ALL locally measured
EPROCESS layouts, reading every required page independently (never assuming
contiguous physical pages). No arbitrary frame reads, no full scan. Then a
PEB->ICImage->PE read-back through gdrv3 iff a DTB survives PID/layout gates.
Output: temp/_h393_layout.txt. Read-only, own process query + gdrv3.
"""
import os
import struct
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "ext"))
import gio
import dumplive as dl
import qk_va
import subprocess

OUT = os.path.join(os.path.dirname(__file__), "_h393_layout.txt")
PID = 14008
NAME = b"r5apex_dx12.ex\0"
HITS = [0x1860DA5E0, 0x1DB967920, 0x2D87FB490, 0x370C7BFF2,
        0x385F57E0B, 0x63DFF3FF2, 0x2D5C61E0B, 0x5D7F09350]
LAYOUTS = (("26200", 0x338, 0, 0x28, 0x1D0, 0x247),
           ("26200-alt", 0x3A8, 0x70, 0x98, 0x240, 0x247))


def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")


def read(g, pa, size):
    if not g.is_ram(pa):
        raise OSError("RAM guard")
    return g.read_phys(pa, size)


open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"' + os.path.abspath(__file__) + '"'))
g = gio.Gio(chunk=0x1000)
rr, note = dl.usable_ranges(g.ram_top, None, None)
g.is_ram = qk_va.Ram(rr).page_ok
say("=== h393 EPROCESS layout gate %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
say("ranges=%d note=%s pid=%d" % (len(rr), note, PID))
candidates = []
try:
    for hit in HITS:
        for tag, noff, toff, doff, poff, pcoff in LAYOUTS:
            obj = hit - noff
            begin = (obj + toff) & ~0xFFF
            end = obj + 0x3B0
            chunks = []
            for pa in range(begin, end + 0x1000, 0x1000):
                try:
                    chunks.append((pa, read(g, pa, 0x1000)))
                except OSError as e:
                    say("read hit=%#x layout=%s page=%#x err=%s" %
                        (hit, tag, pa, e))
            def get_at(addr, n):
                for pa, buf in chunks:
                    if pa <= addr and addr + n <= pa + 0x1000:
                        return buf[addr - pa:addr - pa + n]
                return None
            if get_at(obj + noff, 15) != NAME:
                continue
            tb, pid_b, dtb_b = get_at(obj + toff, 1), get_at(obj + poff, 8), get_at(obj + doff, 8)
            if not tb or not pid_b or not dtb_b:
                continue
            typ = tb[0]
            dtb = struct.unpack("<Q", dtb_b)[0]
            live = struct.unpack("<Q", pid_b)[0]
            say("hit=%#x layout=%s obj=%#x type=%d pid=%d dtb=%#x prio=%s" %
                (hit, tag, obj, typ, live, dtb, get_at(obj + pcoff, 1)))
            if typ != 3 or live != PID or not (0x1000 <= dtb < g.ram_top):
                continue
            # Validate the process-linked structure itself, not a random dtb.
            pool = get_at(obj - 0x10, 0x10)
            if pool:
                say("pool_prefix=%s" % pool.hex())
            candidates.append((obj, dtb, tag, hit))
    say("VALID_DTBS=%d" % len(candidates))
    if not candidates:
        say("RESULT: no_PID_verified_EPROCESS")
        say("VERDICT: BLOCKED_LAYOUT - still no translation")
        sys.exit(3)
    for obj, dtb, tag, hit in candidates:
        say("TRY object=%#x dtb=%#x layout=%s" % (obj, dtb, tag))
        try:
            w = dl.Walk(g, dtb)
            peb = qk_va._peb_va(PID)
            raw = w.read(peb + 0x10, 8) if False else None
            # Walk is the local API; Reader handles page bounds/retries.
            rd = qk_va.Reader(g, dtb)
            raw = rd.read(peb + 0x10, 8)
            if not raw:
                say("WALK_BLOCKED at PEB/PDPT/PD/PT: %s" % dl.probe_dtb(g, dtb))
                continue
            base = struct.unpack("<Q", raw)[0]
            image_pa = rd.page_pa(base)
            page = rd.read(base, 0x1000)
            meta = dl.validate_pe(page) if page else None
            say("base=%#x image_pa=%s PE=%s" %
                (base, image_pa, meta if meta else "no"))
            if not meta or meta["size"] != 0xDFB8000:
                continue
            say("RESULT: DTB=%#x image_va=%#x image_pa=%#x" % (dtb, base, image_pa))
            qk_va.save_cache(PID, dtb, base)
            say("VERDICT: PASS - PID-verified DTB read Apex PE through gdrv3")
            sys.exit(0)
        except OSError as e:
            say("WALK_ERROR=%s" % e)
    say("RESULT: DTB found, translation unreadable")
    say("VERDICT: BLOCKED_WALK - see table-read result")
except Exception:
    import traceback
    say("EXC=" + traceback.format_exc().replace("\n", " | "))
    say("VERDICT: FAIL - gate exception, no claim")
    sys.exit(9)
finally:
    g.close()