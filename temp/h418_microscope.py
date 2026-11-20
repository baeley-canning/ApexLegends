# -*- coding: utf-8 -*-
r"""h418_microscope.py -- hexdump the neighbourhoods of pid-lit name hits.

Statistics amortised single true positives to invisibility (h417 census);
direct eyeballs settle whether an EPROCESS-looking body sits near tonight's
harvested name strings.  For each selected (nm,pid,hit) prints a labelled
hexdump of [hit-0x380, hit+0x80) and marks ladder positions where the joint
grammar lights >=2 fields.

Read-only; R10 honoured.
"""
import ctypes
import ctypes.wintypes as wt
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
EXT = os.path.join(ROOT, "ext")
sys.path.insert(0, EXT)
import gio                       # noqa: E402
import dumplive as dl            # noqa: E402
import qk_va as VA               # noqa: E402

OUT = os.path.join(HERE, "h418_microscope.txt")
PRE, POST, STEP = 0x380, 0x80, 8


def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(str(s) + "\n")


PICKS = [("explorer.exe", 11068, 0x68e6c2084),
         ("explorer.exe", 11068, 0x6709f6708),
         ("dwm.exe", 1960, 0x4f5a30da8),
         ("dwm.exe", 1960, 0x660cc2068)]


def main():
    t0 = time.time()
    open(OUT, "w", encoding="utf-8").close()
    say("h418 start %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
    try:
        g = gio.Gio(chunk=0x10000)
        _ = g.read_phys(0x1000, 8)
    except Exception as e:                        # noqa: BLE001
        say("transport unusable: %r" % e)
        say("VERDICT: TRANSPORT_DOWN")
        return 5
    ranges, _n = dl.usable_ranges(g.ram_top, None, None)
    ram = VA.Ram(ranges)
    g.is_ram = ram.page_ok

    for nm, pid, hit in PICKS:
        lo = (hit - PRE) & ~0xF
        hi = hit + POST
        try:
            blob = g.read_phys(lo, hi - lo)
        except OSError as e:
            say("[%s %d] hit=%#x read fault %s" % (nm, pid, hit, e))
            continue
        say("[%s %d] WINDOW hit=%#x span=%#x..%#x (%d B)"
            % (nm, pid, hit, lo, hi, len(blob)))
        for row_lo in range(lo, hi, 0x10):
            k = row_lo - lo
            chunk = blob[k:k + 0x10]
            hexpart = " ".join("%02x" % b for b in chunk)
            asc = "".join(chr(b) if 0x20 <= b < 0x7F else "." for b in chunk)
            marks = ""
            for d in range(row_lo - (hit - 0x400),
                           row_lo + 0x10 - (hit - 0x400), STEP):
                base = hit - d
                if not (row_lo <= base < row_lo + 0x10) or base < lo:
                    continue
                off = base - lo
                w = blob[off:off + 0x650]
                if len(w) < 0x650:
                    continue
                dtb = struct.unpack_from("<Q", w, 0x28)[0]
                peb = struct.unpack_from("<Q", w, 0x2E0)[0]
                tok = struct.unpack_from("<Q", w, 0x248)[0] >> 48
                fp = any(struct.unpack_from("<Q", w, o)[0] == pid
                         or struct.unpack_from("<Q", w, o)[0] &
                         0xFFFFFFFF == pid for o in (0x1D0, 0x240, 0x2E8))
                lit = (fp + (0x1000 < peb < 0x800000000000 and not peb & 7)
                       + (tok == 0xFFFF)
                       + (0x1000 <= dtb < g.ram_top and not dtb & 0xFFF))
                if lit >= 2:
                    marks += " <-- d=%#x base=%#x type=%d lit=%d" % (
                        d, base, w[0], lit)
            say("  %012X  %s  |%s|%s" % (row_lo, hexpart, asc, marks))
        say("")
    say("--- elapsed %.1fs" % (time.time() - t0))
    say("VERDICT: EYES_ONLY (manual inspection of dump above)")
    return 0


if __name__ == "__main__":
    try:
        rc = main()
    except Exception as e:                        # noqa: BLE001
        import traceback
        say("EXC %r" % e)
        say(traceback.format_exc())
        rc = 9
    say("h418 end rc=%d" % rc)
    sys.exit(rc)
