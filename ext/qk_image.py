r"""qk_image.py -- find the game image in PHYSICAL memory (route B: static offsets).

Every real external cheat does `module_base + static_offset`. We could not, because we
had no module base (no DTB). But the image itself is in physical RAM and is uniquely
identifiable: MZ + SizeOfImage = 0xDFB8000 (234 MB, Apex's exe). Once the base page is
known, `base_pa + section_rva` is a direct read IF the loader kept sections contiguous
- which this tool measures instead of assuming.

Usage: qk_image.py [--out=FILE] [--no-elevate]
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gio            # noqa: E402
import dumplive as dl  # noqa: E402

ROOT = os.path.dirname(HERE)
TMP = os.path.join(ROOT, "temp")
OUT = None
LOG = []
SIZE_LO, SIZE_HI = 0x0DF00000, 0x0E100000
RVAS = (0x1B4DFA0, 0x1B4DFA0 + 0x40, 0x022EE01, 0x23F6A90, 0x01E7D4B8)


def out(s):
    line = str(s).encode("ascii", "replace").decode("ascii")   # console is cp1252
    print(line)
    LOG.append(line)
    if OUT:
        with open(OUT, "a", encoding="utf-8") as f:
            f.write(line + "\n")


def set_out(p):
    global OUT
    OUT = os.path.abspath(p) if p else None
    if OUT:
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("")


def arg(name, default=None, cast=str):
    for i, a in enumerate(sys.argv):
        if a == "--" + name and i + 1 < len(sys.argv):
            return cast(sys.argv[i + 1])
        if a.startswith("--" + name + "="):
            return cast(a.split("=", 1)[1])
    return default


def flag(name):
    return ("--" + name) in sys.argv


def matrix_score(m):
    """View-projection in either convention (m15=+-1 GL style, m11=+-1 D3D style)."""
    for v in m:
        if v != v or abs(v) > 1.0e5:
            return 0
    if not (abs(abs(m[15]) - 1.0) < 0.01 or abs(abs(m[11]) - 1.0) < 0.01):
        return 0
    small = sum(1 for i in (0, 1, 2, 4, 5, 6, 8, 9, 10) if abs(m[i]) <= 2.0)
    if small < 6:
        return 0
    if not any(100.0 < abs(m[i]) < 1.0e5 for i in (12, 13, 14, 3, 7, 11)):
        return 0
    return 30 + small * 2


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def check_image(g, pa):
    """(lf, size, stamp, nsec, optsize) when pa really is the game image."""
    try:
        h = dl.retry_phys(g, pa, 0x400, tries=2)
    except OSError:
        return None
    if len(h) < 0x200 or h[:2] != b"MZ":
        return None
    lf = u32(h, 0x3C)
    if not (0x40 <= lf <= 0x3F0) or h[lf:lf + 4] != b"PE\x00\x00":
        return None
    if u16(h, lf + 4) != 0x8664:
        return None
    size = u32(h, lf + 0x50)
    if not (SIZE_LO <= size <= SIZE_HI):
        return None

    return (lf, size, u32(h, lf + 8), u16(h, lf + 6), u16(h, lf + 0x14))


def main():
    set_out(arg("out", os.path.join(TMP, "qk_image_%d.txt" % os.getpid())))
    if not dl.elevation() and ("--no-elevate" not in sys.argv):
        cmd = " ".join('"%s"' % a if " " in a else a for a in sys.argv) + " --no-elevate"
        print(dl.run_elevated(cmd))
        return 0

    out("===== qk_image: locate r5apex_dx12 in physical RAM =====")
    out("out=%s" % OUT)
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        out("gio: %s" % e)
        return 2
    try:
        ranges, note = dl.usable_ranges(g.ram_top, None, None)
        out("ram_top=%#x ranges=%d (%s)" % (g.ram_top, len(ranges), note))
        hits = []
        n = 0
        for rlo, rhi in ranges:
            pa = (rlo + 7) & ~7
            while pa + 0x10000 <= rhi:
                n += 1
                if (n & 0x3FFF) == 0:
                    out("  scanned %d chunks, %d image hits" % (n, len(hits)))
                try:
                    blk = dl.retry_phys(g, pa, 0x10000, tries=1)
                except OSError:
                    pa += 0x10000
                    continue
                i = blk.find(b"MZ")
                while i >= 0:
                    r = check_image(g, pa + i)
                    if r:
                        hits.append((pa + i, r))
                        out("  IMAGE at %#012x SizeOfImage=%#x stamp=%#x sections=%d"
                            % (pa + i, r[1], r[2], r[3]))
                    i = blk.find(b"MZ", i + 1)
                pa += 0x10000
        out("scanned %d chunks, %d image hit(s)" % (n, len(hits)))
        if not hits:
            out("RESULT: no-image")
            out("VERDICT: FAIL - r5apex_dx12 not in RAM (game not running?)")
            return 8
        pa, (lf, size, stamp, nsec, optsize) = max(hits, key=lambda h: h[1][1])
        out("chosen image_pa=%#012x size=%#x sections=%d optsize=%#x"
            % (pa, size, nsec, optsize))
        hdr = dl.retry_phys(g, pa + lf + 0x18 + optsize, nsec * 40, tries=3)
        contig = 0
        for k in range(nsec):
            s = hdr[k * 40:(k + 1) * 40]
            if len(s) < 40:
                break
            name = s[:8].rstrip(b"\x00").decode("ascii", "replace")
            vsize, vaddr, ch = u32(s, 8), u32(s, 12), u32(s, 36)
            try:
                head = dl.retry_phys(g, pa + vaddr, 16, tries=2)
                nz = sum(1 for b in head if b)
                ok = nz >= 6
                contig += 1 if ok else 0
                out("  %-8s va=%#010x vsize=%#09x wr=%d ex=%d head=%s contiguous=%s"
                    % (name, vaddr, vsize, 1 if ch & 0x80000000 else 0,
                       1 if ch & 0x20000000 else 0, head[:8].hex(),
                       "yes" if ok else "no/unclear"))
            except OSError:
                out("  %-8s va=%#010x (read fault)" % (name, vaddr))
        out("  sections whose base_pa+va reads as real data: %d/%d" % (contig, nsec))
        for rva in RVAS:
            try:
                b = dl.retry_phys(g, pa + rva, 64, tries=2)
            except OSError:
                out("  rva %#010x: read fault" % rva)
                continue
            m = struct.unpack("<16f", b)
            finite = all(v == v and abs(v) < 1e6 for v in m)
            out("  rva %#010x finite=%s" % (rva, finite))
            for r in range(4):
                out("     [%d] %11.4f %11.4f %11.4f %11.4f"
                    % (r, m[r * 4], m[r * 4 + 1], m[r * 4 + 2], m[r * 4 + 3]))
        if flag("data"):
            dv = dsz = None
            for k in range(nsec):
                s = hdr[k * 40:(k + 1) * 40]
                if len(s) >= 40 and s[:8].rstrip(b"\x00") == b".data":
                    dv, dsz = u32(s, 12), u32(s, 8)
                    break
            if dsz:
                out("  scanning .data va=%#x size=%#x (%d MB) for matrices"
                    % (dv, dsz, dsz // 1048576))
                best = []
                cur, end, scanned = pa + dv, pa + dv + dsz, 0
                while cur + 0x10000 <= end:
                    try:
                        blk = dl.retry_phys(g, cur, 0x10000, tries=1)
                    except OSError:
                        cur += 0x10000
                        continue
                    scanned += len(blk)
                    for pat in (b"\x00\x00\x80\x3f", b"\x00\x00\x80\xbf"):
                        i = blk.find(pat)
                        while i >= 0:
                            st = i - 60
                            if st >= 0 and (st & 3) == 0 and st + 64 <= len(blk):
                                m = struct.unpack_from("<16f", blk, st)
                                sc = matrix_score(m)
                                if sc:
                                    best.append((sc, cur + st - pa, m))
                                    best.sort(reverse=True)
                                    del best[8:]
                            i = blk.find(pat, i + 4)
                    cur += 0x10000
                out("  .data scanned=%d bytes, matrix candidates=%d" % (scanned, len(best)))
                if flag("watch") and best:
                    out("  re-reading the %d candidate(s) after 1.5 s - the live matrix moves"
                        % len(best))
                    time.sleep(1.5)
                    for sc, rva, m0 in best:
                        try:
                            b1 = dl.retry_phys(g, pa + rva, 64, tries=2)
                        except OSError:
                            out("   rva=%#010x re-read fault" % rva)
                            continue
                        m1 = struct.unpack("<16f", b1)
                        d = max(abs(x - y) for x, y in zip(m0, m1))
                        out("   rva=%#010x max_delta=%.6f%s"
                            % (rva, d, "   <-- CHANGED (live view matrix)" if d > 1e-4 else ""))


        out("RESULT: image_pa=%#x contiguous_sections=%d/%d stamp=%#x"
            % (pa, contig, nsec, stamp))
        out("VERDICT: %s - %s"
            % ("PASS" if contig >= nsec - 1 else "PARTIAL",
               "base_pa+rva works: static offsets are a direct read"
               if contig >= nsec - 1 else
               "sections NOT contiguous: static offsets need a VA->PA walk"))
        return 0
    finally:
        try:
            g.close()
        except Exception:                        # noqa: BLE001
            pass


if __name__ == "__main__":
    sys.exit(main())

