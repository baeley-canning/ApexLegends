r"""_qk_dtb_probe2.py -- targeted DTB grab, 16-32 GB band only.

Every EPROCESS name-hit on this boot lives in 16-32 GB (0x4062..0x7E45..), and that
band scans in ~40 s.  Chain: name sweep (16 B needle) -> EPROCESS base (type byte 3,
step 1 because hits are off-grid) -> confirm by UniqueProcessId -> DTB = base+0x28 ->
walk PEB -> ImageBase -> MZ.  Writes qk_va's dtb cache on success so qk_world skips
discovery completely.
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

OUT = os.path.join(HERE, "_qk_dtb2.txt")
BAND = 0x400000000, 0x800000000


def walk_page(g, fr, va):
    t = fr & 0xFFFFFFFFFF000
    for sh in (39, 30, 21):
        b = g.read_phys(t + ((va >> sh) & 0x1FF) * 8, 8)
        e = struct.unpack("<Q", b)[0]
        if not (e & 1):
            return None
        if (e & 0x80) and sh == 21:
            return (e & 0xFFFFFFFFFF000) + (va & 0x1FFFFF)
        t = e & 0xFFFFFFFFFF000
    return t + (va & 0xFFF)


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
    g = gio.Gio(chunk=0x40000)
    ranges, _ = dl.usable_ranges(g.ram_top, None, None)
    band = [(max(lo, BAND[0]), min(hi, BAND[1]))
            for lo, hi in ranges if hi > BAND[0] and lo < BAND[1]]
    say("band %#x..%#x in %d range(s)" % (BAND[0], BAND[1], len(band)))

    dl.NAME = b"r5apex_dx12.exe\x00"
    hits, skipped, chunks, rescued = dl.name_hits(g, band)
    say("hits=%d skipped=%d" % (len(hits), skipped))

    # -- diagnostics first: for the first few hits, show the region, any pid
    # occurrence (step 1: hits are off-grid), and every type-3 byte with context.
    for hit in hits[:6]:
        try:
            blob = g.read_phys(hit - 0x800, 0x900)
        except OSError as e:
            say("hit=%#x fault %s" % (hit, e))
            continue
        say("=== hit=%#x pre=%r post=%r"
            % (hit, blob[0x7F0:0x800], blob[0x80F:0x828]))
        for off in range(0, len(blob) - 8):
            v = struct.unpack_from("<Q", blob, off)[0]
            if v == pid:
                say("  pid@%+#x (base-if-pid0x440=%+#x)" % (off - 0x800, off - 0x800 - 0x440))
        n3 = 0
        for d in range(0x200, 0x800):
            base = hit - d
            if base < 0x10000:
                continue
            try:
                tb = g.read_phys(base, 1)[0]
            except OSError:
                continue
            if tb != 3:
                continue
            n3 += 1
            if n3 <= 8:
                try:
                    win = g.read_phys(base, 0x30)
                except OSError:
                    win = b""
                say("  byte3 d=%#x base=%#x win=%s" % (d, base, win.hex()))
        say("  type3 count=%d" % n3)

    good = []
    for hit in hits:
        for d in range(0x200, 0x800):
            base = hit - d
            if base < 0x10000:
                continue
            try:
                if g.read_phys(base, 1)[0] != 3:
                    continue
            except OSError:
                continue
            poff = None
            for po in (0x440, 0x448, 0x438, 0x450, 0x430, 0x458, 0x460, 0x470):
                try:
                    if struct.unpack("<Q", g.read_phys(base + po, 8))[0] == pid:
                        poff = po
                        break
                except OSError:
                    continue
            if poff is None:
                continue
            try:
                nm = g.read_phys(hit, 15)
                dtb = struct.unpack("<Q", g.read_phys(base + 0x28, 8))[0]
            except OSError:
                continue
            say("EPROCESS hit=%#x d=%#x base=%#x pid@+%#x name=%r dtb=%#x"
                % (hit, d, base, poff, nm, dtb))
            try:
                peb_pa = walk_page(g, dtb, 0x38C000 if True else 0)
            except OSError as e:
                say("  walk fault: %s" % e)
                continue
            if not peb_pa:
                say("  walk: no PEB mapping")
                continue
            ib = struct.unpack("<Q", g.read_phys(peb_pa + 0x10, 8))[0]
            say("  PEB=%#x ImageBase=%#x" % (peb_pa, ib))
            if not ib or ib >= 0x7FFFFFFFFFFF:
                continue
            try:
                bpa = walk_page(g, dtb, ib)
                mz = g.read_phys(bpa, 2) if bpa else None
            except OSError:
                mz = None
            say("  image pa=%s mz=%r" % (("%#x" % bpa) if bpa else "none", mz))
            if mz == b"MZ":
                good.append((dtb, ib))
    if good:
        VA.save_cache(pid, good[0][0], good[0][1])
        say("CACHE WRITTEN dtb=%#x base=%#x" % good[0])
        say("VERDICT: PASS")
    else:
        say("VERDICT: PARTIAL")
        return 3
    return 0


try:
    sys.exit(main())
except Exception as e:                      # noqa: BLE001
    import traceback
    say("EXC %r" % e)
    say(traceback.format_exc())
    sys.exit(9)
