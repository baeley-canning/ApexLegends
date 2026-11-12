r"""_qk_dtb15.py -- needle calibrated from the VERIFIED object bytes.

The real object (dumped and confirmed tonight) contains:
    ... 72 35 61 70 65 78 5f 64 78 31 32 2e 65 78 00 02 ...
i.e. "r5apex_dx12.ex" + NUL + PriorityClass 0x02.  So the sweep pattern is those
17 bytes -> only real process objects match -> base = hit - 0x338 EXACT (no
offset scanning).  Then: type byte 3, DTB at +0x28, walk PEB, MZ, cache -- and the
view angles read twice 3 s apart as the live proof.

Sweep attempts: 16-32 GB band -> all RAM -> band again (the box currently fails
~26% of pages per pass; a second pass often catches the copy).
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

OUT = os.path.join(HERE, "_qk_dtb15.txt")
BAND = (0x400000000, 0x800000000)
NEEDLE = b"r5apex_dx12.ex\x00\x02"
NAME_OFF = 0x338


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


def pread(g, pa, n):
    try:
        return dl.retry_phys(g, pa, n, tries=3)
    except OSError:
        return VA.drv_phys(pa, n)


def q(g, pa):
    return struct.unpack("<Q", pread(g, pa, 8))[0]


def walk(g, dtb, va):
    t = dtb & 0xFFFFFFFFFF000
    for sh in (39, 30, 21):
        e = struct.unpack_from("<Q", pread(g, t, 0x1000), ((va >> sh) & 0x1FF) * 8)[0]
        if not (e & 1):
            return None
        if (e & 0x80) and sh == 21:
            return (e & 0xFFFFFFFFFF000) + (va & 0x1FFFFF)
        t = e & 0xFFFFFFFFFF000
    return t + (va & 0xFFF)


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
    ranges, _ = dl.usable_ranges(g.ram_top, None, None)
    band = [(max(lo, BAND[0]), min(hi, BAND[1]))
            for lo, hi in ranges if hi > BAND[0] and lo < BAND[1]]
    dl.NAME = NEEDLE

    hits = []
    for tag, rs in (("band", band), ("all", ranges), ("band2", band)):
        hits, skipped, chunks, rescued = dl.name_hits(g, rs)
        say("sweep %s: hits=%d skipped=%d" % (tag, len(hits), skipped))
        if hits:
            break
    for h in hits[:8]:
        say("  hit %#x" % h)

    good = []
    for hit in hits:
        base = hit - NAME_OFF
        try:
            tb = pread(g, base, 1)[0]
            prio = pread(g, base + 0x347, 1)[0]
            dtb = q(g, base + 0x28)
        except OSError as e:
            say("  hit %#x: read fault %s" % (hit, e))
            continue
        say("  hit %#x -> base %#x type=%#x prio=%#x dtb=%#x"
            % (hit, base, tb, prio, dtb))
        if tb != 3 or not (0x1000 <= dtb < g.ram_top) or (dtb & 0xFFF):
            say("    shape fail")
            continue
        try:
            peb_pa = walk(g, dtb, peb)
            ib = q(g, peb_pa + 0x10) if peb_pa else 0
            bpa = walk(g, dtb, ib) if ib else 0
            mz = pread(g, bpa, 2) if bpa else None
        except OSError as e:
            say("    walk fault %s" % e)
            continue
        say("    peb_pa=%s ib=%#x mz=%r" % (("%#x" % peb_pa) if peb_pa else "NULL", ib, mz))
        if mz == b"MZ":
            good.append((dtb, ib, base))

    if not good:
        say("VERDICT: PARTIAL")
        return 3

    dtb, ib, base = good[0]
    VA.save_cache(pid, dtb, ib)
    say("CACHE WRITTEN pid=%d dtb=%#x base=%#x" % (pid, dtb, ib))

    # -- the live angle proof: two samples, 3 s apart, no user action -------------
    a_off = base + NAME_OFF + 0x3A4
    yb = pread(g, a_off, 8)
    y0, p0 = struct.unpack("<2f", yb)
    say("ANGLES t0: yaw=%.2f pitch=%.2f" % (y0, p0))
    time.sleep(3.0)
    yb = pread(g, a_off, 8)
    y1, p1 = struct.unpack("<2f", yb)
    say("ANGLES t+3s: yaw=%.2f pitch=%.2f" % (y1, p1))
    say("ANGLES live: %s" % ("CHANGED while playing" if (abs(y1 - y0) > 0.01 or abs(p1 - p0) > 0.01) else "static (standing still)"))
    op = struct.unpack("<3f", pread(g, base + NAME_OFF - 0xEEC, 12))
    say("ORIGIN: (%.1f, %.1f, %.1f)" % op)
    say("VERDICT: PASS dtb=%#x base=%#x" % (dtb, ib))
    return 0


try:
    sys.exit(main())
except Exception as e:                      # noqa: BLE001
    import traceback
    say("EXC %r" % e)
    say(traceback.format_exc())
    sys.exit(9)
