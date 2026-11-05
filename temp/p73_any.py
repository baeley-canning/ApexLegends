r"""p73_any.py -- find page-table entries pointing at a given PA, any index.

Bottom-up table discovery for a page whose VA is unknown: the PTE value itself
is the anchor, so only the process that maps that page can match.
Read-only.  Verified re-read per hit; PS bit clear; page must be RAM.
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio
import dumplive as dl

CHUNK = 0x10000
PAGE = 0x1000
CAP = 500
PA = 0
OUT = ""


MODE_LABEL = ""
LO = None
HI = None
PS = False
TRANS = False


def main():
    global PA, OUT, LO, HI, PS, TRANS
    for a in sys.argv[1:]:
        if a.startswith("--pa="):
            PA = int(a[5:], 0)
        elif a.startswith("--lo="):
            LO = int(a[5:], 0)
        elif a.startswith("--hi="):
            HI = int(a[5:], 0)
        elif a == "--ps":
            PS = True
        elif a == "--trans":
            TRANS = True
    if not PA:
        print("need --pa")
        return 2
    tag = "%x" % PA
    if LO:
        tag += "_%x" % LO
    OUT = os.path.join(HERE, "_p73_any_%s.txt" % tag)

    def accept(q):
        """match test: same frame; PS required in ps mode, forbidden otherwise.
        --trans also accepts a transition entry (bit 10, present clear): the
        page is trimmed, the PFN still names the frame and the content is
        intact, it is only unmapped until touched."""
        if (q & 0x000FFFFFFFFFF000) != PA:
            return False
        if PS:
            return bool(q & 0x80)
        if q & 0x80:
            return False
        if TRANS:
            return bool(q & 0x400) and not q & 0x1
        return bool(q & 1)

    def note(s):
        with open(OUT, "a", encoding="utf-8") as f:
            f.write("%s %s\n" % (time.strftime("%H:%M:%S"), s))

    try:
        os.remove(OUT)
    except OSError:
        pass
    note("start pid=%d" % os.getpid())
    pat = struct.pack("<Q", PA)[2:6]          # PFN bits 16..47 only: bits 48+
                                              # hold the prot-key and NX, which
                                              # differ per PTE
    lines = ["pa=%#x" % PA]
    raw = []
    faults = 0
    t0 = time.time()
    try:
        g = gio.Gio(chunk=CHUNK)
        note("device open")
        try:
            ranges, note2 = dl.usable_ranges(g.ram_top, LO, HI)
            lines.append("ranges=%d %s" % (len(ranges), note2))
            note("ranges=%d %s" % (len(ranges), note2))
            for lo, hi in ranges:
                cur = lo
                note("range %#x-%#x" % (lo, hi))
                while cur < hi:
                    n = min(CHUNK, hi - cur)
                    try:
                        blk = g.read_phys(cur, n)
                    except OSError:
                        faults += 1
                        blk = None
                    if blk is not None:
                        p = blk.find(pat)
                        while p >= 0 and len(raw) < CAP:
                            # a matching entry has the PFN at bits 16.. in a
                            # qword, i.e. the pattern starts at byte 2 of it
                            if (cur + p) & 7 == 2:
                                raw.append(cur + p)
                            p = blk.find(pat, p + 1)
                    cur += n
        finally:
            g.close()
        lines.append("raw=%d faults=%d %.1fs" % (len(raw), faults, time.time() - t0))
        # verify: exact qword, 8-aligned, present, PS clear, page RAM
        g = gio.Gio()
        good = 0
        try:
            for pa in raw:
                page = pa & ~0xFFF
                off = (pa - page) - 2        # pattern starts at +2 inside the entry
                if not g.is_ram(page):
                    continue
                try:
                    q = g.u64(page + off)
                except OSError:
                    continue
                if accept(q):
                    good += 1
                    lines.append("TABLE %#x idx=%d flags=%#x q=%#x"
                                 % (page, off // 8, q & 0xFFF, q))
                elif len(lines) < 60:
                    lines.append("  raw %#x off=%#x q=%#x ps=%d"
                                 % (page, off, q, (q >> 7) & 1))
        finally:
            g.close()
        lines.insert(1, "verified=%d" % good)
    except Exception:
        import traceback
        lines.append("EXC\n" + traceback.format_exc())
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
