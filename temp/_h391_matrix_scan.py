r"""h391 -- targeted scan for the real Apex view-projection in image .data.

h388/h390 proved the qk_image candidates are not the ESP matrix: the two that
project put the census on screen, but their homogeneous row is dominated by the
world Z coefficient, so adding 72 world units of "up" sends the head 180,000
units deep instead of 70 pixels up the screen.

This scan keeps the same physical read path, but scores candidates by the shape
the proven winner had:
  * m15 is near +-1
  * the homogeneous row is dominated by m3 or m7 (world X/Y forward), not m11
  * the census records project on screen and produce boxes

If a candidate passes, it is cached in temp\\qk_offsets.txt for qk_live.py.
"""
import argparse
import math
import os
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
EXT = os.path.join(ROOT, "ext")
for p in (EXT, HERE):
    if p not in sys.path:
        sys.path.insert(0, p)

import dumplive as dl              # noqa: E402
import qk_live as L                # noqa: E402

PONE = b"\x00\x00\x80\x3f"
NONE = b"\x00\x00\x80\xbf"


def parse_image(path):
    base = None
    data_rva = data_size = None
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.search(r"chosen image_pa=(0x[0-9a-fA-F]+)", line)
            if m:
                base = int(m.group(1), 16)
            m = re.search(r"\.data\s+va=(0x[0-9a-fA-F]+)\s+vsize=(0x[0-9a-fA-F]+)", line)
            if m:
                data_rva = int(m.group(1), 16)
                data_size = int(m.group(2), 16)
    return base, data_rva, data_size


def bottom_row_ok(m):
    """True when the homogeneous row is dominated by world X/Y, not Z."""
    if not L.matrix_plausible(m):
        return False
    x, y, z, w = m[3], m[7], m[11], m[15]
    if abs(abs(w) - 1.0) > 0.01:
        return False
    if abs(x) < 100.0 and abs(y) < 100.0:
        return False
    if abs(z) > 100.0:
        return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", default=os.path.join(HERE, "_act_qk_image_live2.txt"))
    ap.add_argument("--out", default=os.path.join(HERE, "_h391_out.txt"))
    ap.add_argument("--no-elevate", action="store_true")
    args = ap.parse_args()

    if not args.no_elevate and not dl.elevation():
        cmd = " ".join('"%s"' % a if " " in a else a for a in sys.argv) + " --no-elevate"
        print(dl.run_elevated(cmd))
        return 0

    out = open(args.out, "w", encoding="utf-8", newline="\n")

    def p(s=""):
        print(s, flush=True)
        out.write(s + "\n")
        out.flush()

    p("=== h391 matrix scan %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
    base, data_rva, data_size = parse_image(args.log)
    p("image_pa=%s .data_rva=%s .data_size=%s"
      % (hex(base) if base else None,
         hex(data_rva) if data_rva is not None else None,
         hex(data_size) if data_size is not None else None))
    if base is None or not data_rva or not data_size:
        p("RESULT: no-image-info")
        p("VERDICT: BLOCKED / PARTIAL (SKIPPED physical gates)")
        out.close()
        return 2

    pid = dl.find_pid()
    if not pid:
        p("RESULT: game-not-running")
        p("VERDICT: PARTIAL (SKIPPED physical gates, R9)")
        out.close()
        return 3

    sess = L.Session(cap=28, base=base, rva=0)
    try:
        rect = L.game_rect(pid) or L.screen_rect()
        w, h = rect[2] - rect[0], rect[3] - rect[1]
        ents = sess.prime()
        p("window=%dx%d entities=%d" % (w, h, len(ents)))
        if not ents:
            p("RESULT: no-positions")
            p("VERDICT: FAIL - census has no live positions")
            return 1

        start = base + data_rva
        end = start + data_size
        cur = start
        scanned = 0
        candidates = 0
        best = None

        while cur + 0x10000 <= end:
            blk = sess.ph.read(cur, 0x10000, tries=1)
            if not blk:
                cur += 0x10000
                continue
            scanned += len(blk)
            for pat in (PONE, NONE):
                i = blk.find(pat)
                while i >= 0:
                    st = i - 60
                    if st >= 0 and (st & 3) == 0 and st + 64 <= len(blk):
                        m = struct.unpack_from("<16f", blk, st)
                        if bottom_row_ok(m):
                            candidates += 1
                            hits = L.score_vp(m, ents, w, h)
                            boxes = L.boxes_for(m, ents, w, h)
                            if hits >= 3 and len(boxes) >= 3:
                                if best is None or len(boxes) > best[2]:
                                    best = (cur + st - base, hits, len(boxes), m)
                    i = blk.find(pat, i + 4)
            cur += 0x10000

        p("scanned=%d bytes candidates=%d" % (scanned, candidates))
        if best is None:
            p("RESULT: no-view-matrix")
            p("VERDICT: PARTIAL - no X/Y-forward candidate projects the census into boxes")
            return 4

        rva, hits, boxes, m = best
        p("best rva=%#010x hits=%d/%d boxes=%d" % (rva, hits, len(ents), boxes))
        p("matrix:")
        for row in range(4):
            p("  [%d] %s" % (row, "  ".join("%12.6f" % v for v in m[row * 4:row * 4 + 4])))

        with open(os.path.join(ROOT, "temp", "qk_offsets.txt"), "w", encoding="utf-8") as f:
            f.write("image_pa=0x%X\nvp_rva=0x%X\n" % (base, rva))
        p("CACHED temp\\qk_offsets.txt image_pa=%#x vp_rva=%#x" % (base, rva))
        p("RESULT: vp_rva=%#x hits=%d/%d boxes=%d" % (rva, hits, len(ents), boxes))
        p("VERDICT: PASS - X/Y-forward candidate projects the census into boxes")
        return 0
    finally:
        sess.ph.close()
        out.close()


if __name__ == "__main__":
    sys.exit(main())

