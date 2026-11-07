r"""_qk_dtb16.py -- three passes, accumulate ALL hits, d-scan every hit.

probe15 lesson: the 17-byte needle found one copy whose base was not hit-0x338, and
its loop stopped after the first pass.  This one:
  sweeps band -> all -> band2, accumulates every hit,
  for EVERY hit scans d 0x300..0x380: type byte 3 -> prio <= 0x10 -> DTB plausible,
  walks PEB -> ImageBase -> MZ, caches, then reads the angles twice as live proof.
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

OUT = os.path.join(HERE, "_qk_dtb16.txt")
BAND = (0x400000000, 0x800000000)
NEEDLE = b"r5apex_dx12.ex\x00\x02"


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
    if not pid:
        say("no game yet - waiting up to 3 min ...")
        for _ in range(90):
            time.sleep(2)
            pid = dl.find_pid()
            if pid:
                break
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
    seen = set()
    for tag, rs in (("band", band), ("all", ranges), ("band2", band)):
        h, skipped, chunks, rescued = dl.name_hits(g, rs)
        say("sweep %s: hits=%d skipped=%d" % (tag, len(h), skipped))
        for x in h:
            if x not in seen:
                seen.add(x)
                hits.append(x)
    say("total unique hits=%d" % len(hits))
    for h in hits[:16]:
        say("  hit %#x" % h)

    good = []
    cand = None
    for hit in hits:
        for d in range(0x300, 0x380):
            base = hit - d
            try:
                if pread(g, base, 1)[0] != 3:
                    continue
                prio = pread(g, base + 0x347, 1)[0]
                dtb = q(g, base + 0x28)
            except OSError:
                continue
            if prio > 0x10 or not (0x1000 <= dtb < g.ram_top) or (dtb & 0xFFF):
                continue
            cand = (base, d)
            say("CAND hit=%#x d=%#x base=%#x prio=%#x dtb=%#x" % (hit, d, base, prio, dtb))
            if not peb:
                continue
            try:
                peb_pa = walk(g, dtb, peb)
            except OSError as e:
                say("  walk fault %s" % e)
                continue
            if not peb_pa:
                say("  no PEB")
                continue
            ib = q(g, peb_pa + 0x10)
            say("  PEB=%#x ImageBase=%#x" % (peb_pa, ib))
            if not ib or ib >= 0x7FFFFFFFFFFF:
                continue
            try:
                bpa = walk(g, dtb, ib)
                mz = pread(g, bpa, 2) if bpa else None
            except OSError:
                mz = None
            say("  mz=%r" % mz)
            if mz == b"MZ":
                good.append((dtb, ib, base, d))
                break
        if good:
            break

    if not good:
        if cand:
            base, d = cand
            try:
                with open(os.path.join(HERE, "qk_object_%d.txt" % pid), "w") as f:
                    f.write("pid=%d\nbase=%#x\nd=%#x\ndtb=%#x\n" % (pid, base, d, dtb))
                say("object saved: qk_object_%d.txt" % pid)
            except OSError:
                pass
            a = base + d + 0x3A4
            y0, p0 = struct.unpack("<2f", pread(g, a, 8))
            say("ANGLES(obj-direct) t0: yaw=%.2f pitch=%.2f" % (y0, p0))
            time.sleep(3.0)
            y1, p1 = struct.unpack("<2f", pread(g, a, 8))
            say("ANGLES(obj-direct) t+3s: yaw=%.2f pitch=%.2f" % (y1, p1))
            op = struct.unpack("<3f", pread(g, base + d - 0xEEC, 12))
            say("ORIGIN(obj-direct): (%.1f, %.1f, %.1f)" % op)
            say("VERDICT: PARTIAL - walk blocked, angles+origin OK, dtb=%#x" % dtb)
        else:
            say("VERDICT: PARTIAL - no candidate")
        return 3
    dtb, ib, base, d = good[0]
    VA.save_cache(pid, dtb, ib)
    say("CACHE WRITTEN pid=%d dtb=%#x base=%#x (d=%#x)" % (pid, dtb, ib, d))

    a_off = base + d + 0x3A4
    y0, p0 = struct.unpack("<2f", pread(g, a_off, 8))
    say("ANGLES t0: yaw=%.2f pitch=%.2f" % (y0, p0))
    time.sleep(3.0)
    y1, p1 = struct.unpack("<2f", pread(g, a_off, 8))
    say("ANGLES t+3s: yaw=%.2f pitch=%.2f" % (y1, p1))
    say("ANGLES live: %s" % ("CHANGED while playing" if (abs(y1 - y0) > 0.01 or abs(p1 - p0) > 0.01) else "static"))
    op = struct.unpack("<3f", pread(g, base + d - 0xEEC, 12))
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
