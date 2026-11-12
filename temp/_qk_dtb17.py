r"""_qk_dtb17.py -- validate the KNOWN object (from probe16) with a hardened
transport: alternate gdrv3 and retries with backoff instead of falling through.
hit=0x3352C13B8 d=0x338 base=0x3352C1080 dtb=0x31E50B000.
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio                      # noqa: E402
import dumplive as dl           # noqa: E402
import qk_va as VA              # noqa: E402

OUT = os.path.join(HERE, "_qk_dtb17.txt")
BASE = 0x3352C1080
DTB = 0x31E50B000


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


def pread(g, pa, n, tries=8):
    last = None
    for i in range(tries):
        try:
            return dl.retry_phys(g, pa, n, tries=1)
        except OSError as e:
            last = e
            try:
                return VA.drv_phys(pa, n)
            except OSError:
                pass
            time.sleep(0.03 * (i + 1))
    raise last


def main():
    with open(OUT, "w") as f:
        f.write("")
    dl.PROC_NAME = "r5apex"
    pid = dl.find_pid()
    say("pid=%s" % pid)
    if not pid:
        return 2
    g = gio.Gio(chunk=0x40000)
    peb = VA._peb_va(pid)
    say("PEB=%#x" % (peb or 0))

    tb = pread(g, BASE, 1)[0]
    prio = pread(g, BASE + 0x347, 1)[0]
    dtb = struct.unpack("<Q", pread(g, BASE + 0x28, 8))[0]
    name = pread(g, BASE + 0x338, 16)
    say("object check: type=%#x prio=%#x dtb=%#x name=%r" % (tb, prio, dtb, name))

    def walk(dtb_, va):
        t = dtb_ & 0xFFFFFFFFFF000
        for sh in (39, 30, 21):
            e = struct.unpack_from("<Q", pread(g, t, 0x1000), ((va >> sh) & 0x1FF) * 8)[0]
            if not (e & 1):
                return None, sh
            if (e & 0x80) and sh == 21:
                return (e & 0xFFFFFFFFFF000) + (va & 0x1FFFFF), None
            t = e & 0xFFFFFFFFFF000
        return t + (va & 0xFFF), None

    for attempt in (1, 2):
        try:
            peb_pa, lvl = walk(DTB, peb)
        except OSError as e:
            say("walk%d exc: %s" % (attempt, e))
            time.sleep(0.3)
            continue
        say("walk%d PEB -> %s (absent lvl %s)"
            % (attempt, ("%#x" % peb_pa) if peb_pa else "NULL", lvl))
        if not peb_pa:
            break
        ib = struct.unpack("<Q", pread(g, peb_pa + 0x10, 8))[0]
        say("  ImageBase=%#x" % ib)
        if not ib or ib >= 0x7FFFFFFFFFFF:
            break
        bpa, _ = walk(DTB, ib)
        mz = pread(g, bpa, 2) if bpa else None
        say("  mz=%r" % mz)
        if mz == b"MZ":
            VA.save_cache(pid, DTB, ib)
            say("CACHE WRITTEN pid=%d dtb=%#x base=%#x" % (pid, DTB, ib))
            a = BASE + 0x338 + 0x3A4
            y0, p0 = struct.unpack("<2f", pread(g, a, 8))
            say("ANGLES t0: yaw=%.2f pitch=%.2f" % (y0, p0))
            time.sleep(3.0)
            y1, p1 = struct.unpack("<2f", pread(g, a, 8))
            say("ANGLES t+3s: yaw=%.2f pitch=%.2f" % (y1, p1))
            say("ANGLES live: %s" % ("CHANGED" if (abs(y1 - y0) > 0.01 or abs(p1 - p0) > 0.01) else "static"))
            op = struct.unpack("<3f", pread(g, BASE + 0x338 - 0xEEC, 12))
            say("ORIGIN: (%.1f, %.1f, %.1f)" % op)
            say("VERDICT: PASS dtb=%#x base=%#x" % (DTB, ib))
            return 0
        time.sleep(0.3)
    say("VERDICT: PARTIAL")
    return 3


try:
    sys.exit(main())
except Exception as e:                      # noqa: BLE001
    import traceback
    say("EXC %r" % e)
    say(traceback.format_exc())
    sys.exit(9)
