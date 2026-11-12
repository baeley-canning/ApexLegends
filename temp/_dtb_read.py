"""Try to read the game's DTB frame 0x436ad8000 three ways.

Verified: EPROCESS 0x2aa1d5010 (tag Proc @ 0x...004, Type=3 @+0x70,
name 'r5apex_dx12.ex' @+0x3a8, pid 20612 @+0x240, self-KVA @+0x248)
holds 0x436ad8000 at +0x98 and that frame answers 1450 on every attempt.

1) burst read_phys (does the refusal lift at all)
2) map_phys of the frame, then user-mode memcpy of it (bypasses read_phys)
3) if mapped: PML4 self-test pm[l4idx] == frame, and page_pa() of the self-KVA

Read-only; unmap on the way out so the driver is left as found.
"""
import ctypes
import sys
import time

import numpy as np

sys.path.insert(0, "..\\ext")
import gio
import dumplive as dl

FRAME = 0x436ad8000
SELF_KVA = 0xffffa906d7be7258
OBJ = 0x2aa1d5010
OUT = "_dtb_read_out.txt"
log = open(OUT, "w", encoding="utf-8")


def say(s):
    log.write(s + "\n")
    log.flush()


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % __file__))
        return 0
    g = gio.Gio(chunk=0x1000)
    say("=== dtb frame read %s frame=%#x ===" % (time.strftime("%H:%M:%S"), FRAME))
    ok, last = 0, ""
    t0 = time.time()
    for k in range(20):
        try:
            g.read_phys(FRAME, 0x1000)
            ok += 1
        except OSError as e:
            last = str(e)
        time.sleep(0.01)
    say("read_phys burst 20: ok=%d in %.2fs last=%s" % (ok, time.time() - t0, last))
    say("good-page control 0x100000: %s"
        % ("ok" if _try(g, 0x100000) else "FAIL"))
    pl = _try(g, FRAME)
    va = 0
    try:
        va = g.map_phys(FRAME, 0x1000)
        say("map_phys -> va=%#x" % va)
    except OSError as e:
        say("map_phys: %s" % e)
    if va:
        got = ctypes.string_at(va, 0x1000)
        say("memcpy via mapped va: %d bytes, pm[%d]=%#x"
            % (len(got), (FRAME >> 39) & 0x1FF,
               int(np.frombuffer(got, "<u8")[(FRAME >> 39) & 0x1FF])))
        foot = np.frombuffer(ctypes.string_at(va + (SELF_KVA & 0xFFF), 0x40), "<u8")
        say("at self-KVA slot: %s" % " ".join("%#x" % x for x in foot))
        g.unmap(va, 0x1000)
    say("RESULT: burst_ok=%d map=%s" % (ok, "yes" if va else "no"))
    verb = "PASS" if (ok or va) else "FAIL"
    say("VERDICT: %s - frame %s readable" % (verb, "is" if verb == "PASS" else "is not"))
    g.close()
    return 0 if verb == "PASS" else 1


def _try(g, pa):
    for _k in range(3):
        try:
            return g.read_phys(pa, 0x1000)
        except OSError:
            pass
    return None


if __name__ == "__main__":
    sys.exit(main())
