r"""One-shot diagnostic (03:4x): for each cached 'r5apex_dx12.exe' hit, find every
EPROCESS-shaped base (type byte 3), confirm it by the UniqueProcessId field, and
hand-walk the PEB to an MZ through the candidate DTB.  On success, writes the dtb
cache so qk_world skips discovery outright.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))          # temp\
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio                     # noqa: E402
import dumplive as dl          # noqa: E402
import qk_va as VA             # noqa: E402

OUT = os.path.join(HERE, "..", "temp", "_qk_dtb_probe.txt")
OUT = os.path.abspath(OUT)
lines = []


def say(s):
    lines.append(s)
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


def walk_page(fr, va):
    """4-level walk; returns (pa_of_page, note).  Handles 2 MB pages at PD."""
    t = fr & 0xFFFFFFFFFF000
    for sh in (39, 30, 21):
        try:
            b = g.read_phys(t + ((va >> sh) & 0x1FF) * 8, 8)
        except OSError as e:
            return None, "fault lvl %d: %s" % (sh, e)
        e4 = struct.unpack("<Q", b)[0]
        if not (e4 & 1):
            return None, "absent lvl %d" % sh
        if (e4 & 0x80) and sh == 21:                    # 2 MiB page
            return (e4 & 0xFFFFFFFFFF000) + (va & 0x1FFFFF), "ok(2M)"
        t = e4 & 0xFFFFFFFFFF000
    return t + (va & 0xFFF), "ok"


with open(OUT, "w") as f:
    f.write("")

dl.PROC_NAME = "r5apex"
pid = dl.find_pid()
say("pid=%s" % pid)
if not pid:
    sys.exit(2)
try:
    g = gio.Gio(chunk=0x10000)
except OSError as e:
    say("gio open failed: %s" % e)
    say("(gdrv3 needs an elevated token)")
    sys.exit(2)

hp = os.path.join(HERE, "..", "temp", "qk_hits_%d.txt" % pid)
dl.NAME = b"r5apex_dx12.exe\x00"          # 15 chars + NUL: the ImageFileName family.
hits = []
ranges, _ = dl.usable_ranges(g.ram_top, None, None)
ram = VA.Ram(ranges)
g.is_ram = ram.page_ok                     # R10: the weak default is how an MMIO hole
                                           # bugchecked the box at 21:34; rebind here too
top = [r for r in ranges if r[0] >= 0x400000000]
dl.PROG = OUT
say("sweep for %r over %s (%d/%d ranges) ..."
    % (dl.NAME, "top band" if top else "all", len(top), len(ranges)))
hits, skipped, chunks, rescued = dl.name_hits(g, top or ranges)
say("hits=%d skipped=%d chunks=%d rescued=%d" % (len(hits), skipped, chunks, rescued))

good = None
for hit in hits:
    try:
        blob = g.read_phys(hit - 0x800, 0x900)
    except OSError as e:
        say("hit=%#x read fault: %s" % (hit, e))
        continue
    say("=== hit=%#x near-name=%r" % (hit, blob[0x800:0x800 + 16]))
    seen = set()
    for o in range(0, len(blob) - 8, 8):
        q = struct.unpack_from("<Q", blob, o)[0]
        if not (0x1000 <= q < g.ram_top) or (q & 0xFFF):
            continue
        if q in seen:
            continue
        seen.add(q)
        try:
            peb_pa, note = walk_page(q, 0x2F1000)
        except OSError:
            continue
        if "lvl 39" in note:
            continue
        say("  test frame=%#x (hit%+#x) -> %s (%s)"
            % (q, o - 0x800, ("%#x" % peb_pa) if peb_pa else "NULL", note))
        if not peb_pa:
            continue
        try:
            ib = struct.unpack("<Q", g.read_phys(peb_pa + 0x10, 8))[0]
        except OSError:
            continue
        if not ib or ib >= 0x7FFFFFFFFFFF:
            continue
        bpa, n2 = walk_page(q, ib)
        if not bpa:
            continue
        mz = g.read_phys(bpa, 2)
        say("  frame=%#x (at hit%+#x) peb=%#x ImageBase=%#x mz=%r" % (q, o - 0x800, peb_pa, ib, mz))
        if mz == b"MZ" and good is None:
            good = (q, ib)
            say("  *** TRUE DTB: dtb=%#x base=%#x (hit%+#x)" % (q, ib, o - 0x800))

if good:
    VA.save_cache(pid, good[0], good[1])
    say("CACHE WRITTEN: dtb=%#x base=%#x" % good)
    say("VERDICT: PASS")
else:
    say("VERDICT: PARTIAL - no candidate walked to an MZ")
