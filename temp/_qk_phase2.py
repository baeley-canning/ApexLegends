r"""_qk_phase2.py -- with the object already known (qk_object_<pid>.txt from the
gdrv3-only phase), walk it via apexdrv's MmCopyMemory for the dead page, cache the
dtb, and scan the local object for the bone array.  ~30 s.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio                      # noqa: E402
import dumplive as dl           # noqa: E402
import qk_va as VA              # noqa: E402

OUT = os.path.join(HERE, "_qk_phase2.txt")


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


def main():
    with open(OUT, "w") as f:
        f.write("")
    dl.PROC_NAME = "r5apex"
    pid = dl.find_pid()
    say("pid=%s" % pid)
    if not pid:
        return 2
    p = os.path.join(HERE, "qk_object_%d.txt" % pid)
    if not os.path.exists(p):
        say("no %s - run the gdrv3 phase first" % os.path.basename(p))
        return 3
    k = {}
    with open(p) as f:
        for ln in f:
            if "=" in ln:
                a, b = ln.strip().split("=", 1)
                k[a] = int(b, 16)
    base, d, dtb = k["base"], k["d"], k["dtb"]
    say("object base=%#x d=%#x dtb=%#x" % (base, d, dtb))

    g = gio.Gio(chunk=0x40000)
    if not VA._drv_handle():
        say("no apexdrv handle - walking gdrv3-only")
    peb = VA._peb_va(pid)
    say("PEB=%#x" % (peb or 0))

    def pread(pa, n):
        try:
            return dl.retry_phys(g, pa, n, tries=2)
        except OSError:
            return VA.drv_phys(pa, n)

    def q(pa):
        return struct.unpack("<Q", pread(pa, 8))[0]

    def walk(dtb_, va):
        t = dtb_ & 0xFFFFFFFFFF000
        for sh in (39, 30, 21):
            e = struct.unpack_from("<Q", pread(t, 0x1000), ((va >> sh) & 0x1FF) * 8)[0]
            if not (e & 1):
                return None
            if (e & 0x80) and sh == 21:
                return (e & 0xFFFFFFFFFF000) + (va & 0x1FFFFF)
            t = e & 0xFFFFFFFFFF000
        return t + (va & 0xFFF)

    peb_pa = walk(dtb, peb)
    say("walk PEB -> %s" % (("%#x" % peb_pa) if peb_pa else "NULL"))
    if not peb_pa:
        say("VERDICT: PARTIAL - walk failed")
        return 3
    ib = q(peb_pa + 0x10)
    bpa = walk(dtb, ib) if ib else None
    mz = pread(bpa, 2) if bpa else None
    say("ImageBase=%#x mz=%r" % (ib, mz))
    if mz != b"MZ":
        say("VERDICT: PARTIAL")
        return 3
    VA.save_cache(pid, dtb, ib)
    say("CACHE WRITTEN pid=%d dtb=%#x base=%#x" % (pid, dtb, ib))

    # angles + origin (physical, direct)
    a = base + d + 0x3A4
    y0, p0 = struct.unpack("<2f", pread(a, 8))
    origin = struct.unpack("<3f", pread(base + d - 0xEEC, 12))
    say("ANGLES yaw=%.2f pitch=%.2f  ORIGIN=(%.1f, %.1f, %.1f)" % (y0, p0, *origin))

    # bones: pointer fields in the local object whose target holds a cluster of
    # world triples near the origin (reads via walk; drv_phys for dead pages)
    best = None
    for off in range(0x300, 0x2000, 8):
        try:
            v = q(base + off)
        except OSError:
            continue
        if not (0x10000 <= v < 0x7FFFFFFFFFFF):
            continue
        pa = walk(dtb, v)
        if not pa:
            continue
        try:
            blob = pread(pa, 12 * 56)
        except OSError:
            continue
        near = 0
        top = None
        topdy = -1e9
        for i in range(0, len(blob) - 12, 12):
            px, py, pz = struct.unpack_from("<3f", blob, i)
            if abs(px) > 40000 or abs(py) > 5000 or abs(pz) > 40000:
                continue
            dx, dy, dz = px - origin[0], py - origin[1], pz - origin[2]
            if dx * dx + dz * dz < 600 * 600 and abs(dy) < 300:
                near += 1
                if dy > topdy:
                    topdy = dy
                    top = (px, py, pz)
        if near >= 14 and top and 30 < topdy < 260:
            if best is None or near > best[2]:
                best = (off, v, near, top, topdy)
    if best:
        off, v, near, top, topdy = best
        say("BONES: object+%#x -> VA %#x clustered=%d head_dy=%.1f head=(%.1f, %.1f, %.1f)"
            % (off, v, near, topdy, *top))
        say("VERDICT: PASS - bones found (per-legend head via top bone)")
    else:
        say("VERDICT: PARTIAL - dtb cached, no bone cluster found")
    return 0


try:
    sys.exit(main())
except Exception as e:                      # noqa: BLE001
    import traceback
    say("EXC %r" % e)
    say(traceback.format_exc())
    sys.exit(9)
