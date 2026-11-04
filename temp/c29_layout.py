"""c29: measure the real EPROCESS layout from a live name string.

Scans high RAM for "svchost.exe\\0", derives base = hit - 0x338 and hexdumps
+-0x400 around the base, so type/pid/links offsets are read off the bytes
instead of inferred from a lane assumption.  Read-only, dead spans skipped.
"""
import os
import sys

REPO = os.environ.get("REPO", r"C:\Users\New User\OneDrive\Desktop\cheating")
sys.path.insert(0, os.path.join(REPO, "ext"))
import gio  # noqa: E402
import dumplive as dl  # noqa: E402

OUT = os.path.join(REPO, "temp", "c29_out.txt")
NAMES = (b"svchost.exe\x00", b"explorer.exe\x00", b"conhost.exe\x00")
WIN = 0x10000
L = []


def w(s):
    L.append(s)
    print(s)


def dump(g, base, tag):
    page = base & ~0xFFF
    try:
        p = g.read_phys(page, 0x1000)
    except OSError as e:
        w("  %s base=%#x page=%#x ERR %s" % (tag, base, page, e))
        return
    o = base & 0xFFF
    w("  %s base=%#x pageoff=%#x" % (tag, base, o))
    for off in range(max(0, o - 0x40), min(0x1000, o + 0x380), 0x10):
        row = p[off:off + 0x10]
        w("    +%03x %s  %s" % (off - o, row.hex(" "),
                                "".join(chr(c) if 0x20 <= c < 0x7F else "."
                                        for c in row)))


def main():
    g = gio.Gio()
    try:
        ranges, note = dl.usable_ranges(g.ram_top, 0x100000000, None)
        w("ram_top=%#x %s ranges=%d" % (g.ram_top, note, len(ranges)))
        hits = 0
        for name in NAMES:
            for rlo, rhi in ranges:
                pa = rlo
                while pa < rhi and hits < 3:
                    n = min(WIN, rhi - pa)
                    try:
                        buf = g.read_phys(pa, n)
                    except OSError:
                        pa = (pa + 0x200000) & ~0xFFF
                        continue
                    i = buf.find(name)
                    scan = 0
                    while i >= 0 and hits < 3:
                        hpa = pa + i
                        base = hpa - 0x338
                        o = base & 0xFFF
                        page = base & ~0xFFF
                        try:
                            p = g.read_phys(page, 0x1000)
                        except OSError:
                            p = b""
                        if p and o + 0x350 <= 0x1000 and p[o] == 3:
                            w("HIT %r name at %#x" % (name, hpa))
                            dump(g, base, "obj")
                            hits += 1
                        scan = i + len(name)
                        i = buf.find(name, scan)
                    if hits:
                        break
                    pa += n
                if hits:
                    break
            if hits:
                break
        if not hits:
            w("no hit")
    finally:
        g.close()
        open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")


main()
