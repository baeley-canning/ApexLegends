r"""_qk_dtb14.py -- targeted DTB grab, fresh-boot edition.  Nothing loads, gdrv3 only.

16-32 GB band sweep (where every EPROCESS on this box has lived) -> 15-byte name
pattern -> base = hit-0x338 -> dispatcher type 3 -> PriorityClass at +0x347 ->
UniqueProcessId hunt from +0x100 (this build keeps it at +0x1D0 - the old 0x400+
scans threw the real object away) -> DTB = base+0x28 -> walk PEB (NtQueryInformation,
never hardcoded) -> ImageBase -> MZ -> cache.  apexdrv's drv_phys is the read
fallback when present, but nothing is required for it to exist.
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

OUT = os.path.join(HERE, "_qk_dtb14.txt")
BAND = (0x400000000, 0x800000000)


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


def pread(g, pa, n):
    """gdrv3 first; apexdrv's MmCopyMemory as fallback when it happens to be loaded."""
    try:
        return dl.retry_phys(g, pa, n, tries=3)
    except OSError:
        return VA.drv_phys(pa, n)


def q(g, pa):
    return struct.unpack("<Q", pread(g, pa, 8))[0]


def b1(g, pa):
    return pread(g, pa, 1)[0]


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
    say("PEB via NtQueryInformationProcess = %#x" % (peb or 0))
    ranges, _ = dl.usable_ranges(g.ram_top, None, None)
    band = [(max(lo, BAND[0]), min(hi, BAND[1]))
            for lo, hi in ranges if hi > BAND[0] and lo < BAND[1]]
    dl.NAME = b"r5apex_dx12.ex\x00"
    hits, skipped, chunks, rescued = dl.name_hits(g, band)
    say("hits=%d skipped=%d" % (len(hits), skipped))
    for h in hits[:10]:
        say("  hit %#x" % h)

    good = []
    for hit in hits:
        for d in range(0x300, 0x380):
            base = hit - d
            if base < 0x10000:
                continue
            try:
                if b1(g, base) != 3:
                    continue
                prio = b1(g, base + 0x347)
                dtb = q(g, base + 0x28)
            except OSError:
                continue
            if not (0x1000 <= dtb < g.ram_top) or (dtb & 0xFFF):
                continue
            pido = None
            for off in range(0x100, 0x600, 4):
                try:
                    v = q(g, base + off)
                except OSError:
                    continue
                if v == pid or (v & 0xFFFFFFFF) == pid:
                    pido = off
                    break
            say("CAND hit=%#x d=%#x base=%#x dtb=%#x prio=%#x pid@%s"
                % (hit, d, base, dtb, prio, ("+%#x" % pido) if pido else "no"))
            if not peb:
                continue
            try:
                peb_pa = walk(g, dtb, peb)
            except OSError as e:
                say("  walk fault: %s" % e)
                continue
            if not peb_pa:
                say("  no PEB mapping")
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
            say("  image mz=%r" % mz)
            if mz == b"MZ":
                good.append((dtb, ib))
    if good:
        VA.save_cache(pid, good[0][0], good[0][1])
        say("CACHE WRITTEN pid=%d dtb=%#x base=%#x" % (pid, good[0][0], good[0][1]))
        say("VERDICT: PASS")
        return 0
    say("VERDICT: PARTIAL")
    return 3


try:
    sys.exit(main())
except Exception as e:                      # noqa: BLE001
    import traceback
    say("EXC %r" % e)
    say(traceback.format_exc())
    sys.exit(9)
