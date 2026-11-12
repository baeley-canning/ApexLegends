"""Where does the dead band around a DTB frame start/stop, and does MAP_K survive it?

h33x: read_phys 1450s on page-table frames (old 0x436ad8000, new 0x6ef568000)
while ordinary pool pages read.  This maps the band and tries the untried
mapping primitive 0xC3502019 on the same page.  Read-only, no writes.
"""
import ctypes
import os
import sys

sys.path.insert(0, "..\\ext")
import dumplive as dl          # noqa: E402
import gio                     # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_mk_out.txt")
FRAME = 0x6EF568000
CTRL = 0x436A00000


def say(s):
    line = str(s)
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def rd(g, pa, n=0x1000):
    try:
        return g.read_phys(pa, n)
    except OSError as e:
        return "ERR %s" % e.errno


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % __file__))
        return 0
    open(OUT, "w").close()
    g = gio.Gio(chunk=0x1000)
    say("ram_top=%#x frame=%#x ctrl=%#x" % (g.ram_top, FRAME, CTRL))

    say("--- band map (one page, read_phys) ---")
    base = FRAME & ~0x1FFFFF
    for off in (0, 0x1000, 0x7F000, 0x80000, 0x81000, 0x400000,
                0x480000, 0x500000, 0x560000, 0x567000, 0x568000,
                0x569000, 0x56A000, 0x580000, 0x5C0000, 0x600000,
                0x1FF000):
        pa = base + off
        r = rd(g, pa)
        if isinstance(r, bytes):
            q0 = int.from_bytes(r[:8], "little")
            say("  %#012x (+%#08x) READ ok  q0=%#018x" % (pa, off, q0))
        else:
            say("  %#012x (+%#08x) %s" % (pa, off, r))

    say("--- primitive matrix ---")
    for tag, pa in (("ctrl", CTRL), ("frame", FRAME)):
        r = rd(g, pa)
        say("  %s %#012x read_phys -> %s"
            % (tag, pa, "ok" if isinstance(r, bytes) else r))
        try:
            va = g.map_phys(pa, 0x1000)
            say("  %s %#012x map_phys  -> va=%#x" % (tag, pa, va))
            try:
                q0 = ctypes.c_uint64.from_address(va).value
                say("  %s %#012x   deref      -> q0=%#018x" % (tag, pa, q0))
            except OSError as e:
                say("  %s %#012x   deref FAIL %s" % (tag, pa, e))
        except OSError as e:
            say("  %s %#012x map_phys  -> ERR %s" % (tag, pa, e))
        ok, err, kva = g.map_kernel(pa, 0x1000, g.dst)
        say("  %s %#012x map_kernel-> ok=%s err=%s kva=%s"
            % (tag, pa, ok, err, kva if not ok else "%#x" % kva))
        if ok:
            try:
                q0 = ctypes.c_uint64.from_address(kva).value
                say("  %s %#012x   kva deref  -> q0=%#018x" % (tag, pa, q0))
            except OSError as e:
                say("  %s %#012x   kva deref FAIL %s" % (tag, pa, e))
    say("RESULT: band and primitive matrix written")
    g.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
