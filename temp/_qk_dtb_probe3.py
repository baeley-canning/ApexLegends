r"""_qk_dtb_probe3.py -- the precise one.  Uses the PROVEN anchor recipe from the
repo's own notes (dumplive.py p43x): the 15-char name is stored as 14 chars + NUL
("r5apex_dx12.ex\0"), the EPROCESS base is hit-0x338 (+-drift), the dispatcher type
byte at base+0 must be 3, and the PriorityClass byte at +0x347 right behind the NUL
is the object-vs-string-copy proof.  The 16-byte needle (probe2) was "one byte too
many" and never matched the real object.

Chain: 16-32 GB band sweep -> hits -> base -> type+prio gate -> UniqueProcessId
confirm -> DTB = base+0x28 -> walk PEB -> ImageBase -> MZ -> cache write.
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

OUT = os.path.join(HERE, "_qk_dtb3.txt")
BAND = (0x400000000, 0x800000000)
PEB_HINT = 0x38C000             # this session's PEB VA (pid 12532)


def say(s):
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


def walk_page(g, fr, va):
    t = fr & 0xFFFFFFFFFF000
    for sh in (39, 30, 21):
        b = g.read_phys(t + ((va >> sh) & 0x1FF) * 8, 8)
        e = struct.unpack("<Q", b)[0]
        if not (e & 1):
            return None, "absent lvl %d" % sh
        if (e & 0x80) and sh == 21:
            return (e & 0xFFFFFFFFFF000) + (va & 0x1FFFFF), "ok2M"
        t = e & 0xFFFFFFFFFF000
    return t + (va & 0xFFF), "ok"


def main():
    with open(OUT, "w") as f:
        f.write("")
    dl.PROC_NAME = "r5apex"
    pid = dl.find_pid()
    say("pid=%s" % pid)
    if not pid:
        return 2
    g = gio.Gio(chunk=0x40000)
    ranges, _ = dl.usable_ranges(g.ram_top, None, None)
    band = [(max(lo, BAND[0]), min(hi, BAND[1]))
            for lo, hi in ranges if hi > BAND[0] and lo < BAND[1]]
    say("band %#x..%#x ranges=%d" % (BAND[0], BAND[1], len(band)))

    dl.NAME = b"r5apex_dx12.ex\x00"                 # 15 bytes: the real pattern (p43x)
    hits, skipped, chunks, rescued = dl.name_hits(g, band)
    say("hits=%d skipped=%d" % (len(hits), skipped))

    for hit in hits[:3]:
        try:
            blob = g.read_phys(hit - 0x400, 0x420)
        except OSError as e:
            say("hit=%#x fault %s" % (hit, e))
            continue
        say("=== hit=%#x pre=%r post=%r"
            % (hit, blob[0x3F0:0x400], blob[0x40F:0x41F]))
        for d in range(0x300, 0x380):
            base = hit - d
            try:
                tb = g.read_phys(base, 1)[0]
            except OSError:
                continue
            if tb != 3:
                continue
            try:
                dtb = struct.unpack("<Q", g.read_phys(base + 0x28, 8))[0]
                prio = g.read_phys(base + 0x347, 1)[0]
            except OSError:
                continue
            say("  OBJ d=%#x base=%#x dtb=%#x prio=%#x" % (d, base, dtb, prio))

    good = []
    for hit in hits:
        for d in range(0x300, 0x380):
            base = hit - d
            if base < 0x10000:
                continue
            try:
                if g.read_phys(base, 1)[0] != 3:
                    continue
                prio = g.read_phys(base + 0x347, 1)[0]
                dtb = struct.unpack("<Q", g.read_phys(base + 0x28, 8))[0]
            except OSError:
                continue
            if not (0x1000 <= dtb < g.ram_top) or (dtb & 0xFFF):
                continue
            poff = None
            for po in range(0x3E0, 0x520, 8):
                try:
                    if struct.unpack("<Q", g.read_phys(base + po, 8))[0] == pid:
                        poff = po
                        break
                except OSError:
                    continue
            say("CAND hit=%#x d=%#x base=%#x dtb=%#x prio=%#x pid@%s"
                % (hit, d, base, dtb, prio, ("+%#x" % poff) if poff else "no"))
            if poff is None:
                continue
            try:
                peb_pa, note = walk_page(g, dtb, PEB_HINT)
            except OSError as e:
                say("  walk fault %s" % e)
                continue
            if not peb_pa:
                say("  no PEB (%s)" % note)
                continue
            ib = struct.unpack("<Q", g.read_phys(peb_pa + 0x10, 8))[0]
            say("  PEB=%#x ImageBase=%#x" % (peb_pa, ib))
            if not ib or ib >= 0x7FFFFFFFFFFF:
                continue
            try:
                bpa, _ = walk_page(g, dtb, ib)
                mz = g.read_phys(bpa, 2) if bpa else None
            except OSError:
                mz = None
            say("  image mz=%r" % mz)
            if mz == b"MZ" and (dtb, ib) not in good:
                good.append((dtb, ib))
    if good:
        VA.save_cache(pid, good[0][0], good[0][1])
        say("CACHE WRITTEN dtb=%#x base=%#x" % good[0])
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
