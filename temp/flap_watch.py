# -*- coding: utf-8 -*-
"""flap_watch.py - poll the hostile PML4 frame; on reopening, seize the moment.

Frame 0x3856ea000 (game pid 25548's claimed CR3): readable 21:08 & 22:15,
hard-1450 at 22:25-27 even via retry6.  It flaps.  This daemon:
  cycle : 1 cheap g.read_phys probe of the frame
          + on first success: dl.find_mz(full descent)
          + on MZ: WRITE temp\\qk_dtb_25548.txt (the cache get_map() trusts)
            and exit PASS.  Reverse = delete the cache file.
  exit  : PASS (seeded) | GONE (game pid vanished) | CAP (cycles spent)
Log: temp\\flap_log.txt (append, one line per cycle).  Cycle period 90 s,
hard cap 45 min.  Read-only otherwise; the cache write is documented.
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))

import gio            # noqa: E402
import dumplive as dl  # noqa: E402
try:
    import qk_va as qv  # noqa: E402
except Exception:       # noqa: BLE001
    qv = None

TMP = os.path.join(ROOT, "temp")
LOGP = os.path.join(TMP, "flap_log.txt")
CACHE = os.path.join(TMP, "qk_dtb_25548.txt")
STOP = os.path.join(TMP, "flap_stop.txt")

FRAME = 0x3856EA000
TARGET_PID = 25548
PERIOD = 90
CYCLES = 30


def log(s):
    line = "%s %s" % (time.strftime("%H:%M:%S"), s)
    try:
        with open(LOGP, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass
    print(line)


def pid_alive(pid):
    k32 = None
    try:
        import ctypes
        k32 = ctypes.windll.kernel32
        SYNCHRONIZE = 0x00100000
        h = k32.OpenProcess(SYNCHRONIZE, False, pid)
        if h:
            k32.CloseHandle(ctypes.c_void_p(h))
            return True
        return False
    except Exception:  # noqa: BLE001
        return True   # cannot tell -> assume alive, keep watching


def main():
    log("FLAPWATCH start frame=%#x period=%ds cap=%d" % (FRAME, PERIOD, CYCLES))
    try:
        g = gio.Gio()
    except OSError as e:
        log("gio open failed: %s -> CAP (no transport)" % e)
        return
    ranges, note = dl.usable_ranges(g.ram_top, None, None)
    if qv is not None and hasattr(qv, "Ram"):
        ram = qv.Ram(ranges)
        g.is_ram = ram.page_ok
    log("ram map: %s (%d ranges)" % (note, len(ranges)))

    for cyc in range(CYCLES):
        if os.path.exists(STOP):
            log("cycle%d stopfile -> CAP" % cyc)
            break
        if not pid_alive(TARGET_PID):
            log("cycle%d pid gone -> GONE" % cyc)
            break
        opened = False
        try:
            blk = g.read_phys(FRAME, 0x1000)
            opened = blk is not None and len(blk) == 0x1000
            e0 = struct.unpack_from("<Q", blk)[0] if opened else 0
            log("cycle%d OPEN e0=%#x" % (cyc, e0))
        except OSError as e:
            log("cycle%d shut (%s)" % (cyc, str(e)[:60]))
        if opened:
            r = None
            try:
                r = dl.find_mz(g, FRAME)
            except OSError as e:
                log("cycle%d find_mz fault %s" % (cyc, str(e)[:60]))
            if r:
                try:
                    with open(CACHE, "w", encoding="utf-8") as f:
                        f.write("pid=%d\ndtb=0x%X\nbase=0x%X\n"
                                % (TARGET_PID, FRAME, r[0]))
                    log("cycle%d SEED dtb=0x%X base=0x%X -> PASS"
                        % (cyc, FRAME, r[0]))
                    return
                except OSError as e:
                    log("cycle%d seed write failed %s" % (cyc, e))
            else:
                log("cycle%d open but no PE under descent (contents moved?)" % cyc)
        else:
            if cyc == 0 and os.path.exists(CACHE):
                log("note: stale cache present from earlier seed; leaving untouched")
        time.sleep(PERIOD)
    log("FLAPWATCH end -> CAP")


if __name__ == "__main__":
    main()