r"""h389 -- projection diagnostic for the h388 matrix candidates.

h388 found two candidates that project 26/28 census records on screen but
produce zero boxes.  This probe separates the two possible causes:

  1. the candidate is not the view-projection at all, or
  2. it is the view-projection but `qk_live` is using the wrong vector
     convention (column vs row) or the wrong vertical axis sign.

For each candidate it tries:
  * column-vector projection (what qk_live uses today)
  * row-vector projection
  * head at +72 world units (the current qk_live assumption)
  * head at -72 world units (only to expose an inverted vertical axis)

and reports on-screen hits, box counts, and the first few feet/head
screen coordinates so the next edit is grounded in numbers, not guesses.

Read-only: no state is mutated, every physical read is guarded by the RAM map.
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


def parse_scan(path):
    base = None
    rvas = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.search(r"chosen image_pa=(0x[0-9a-fA-F]+)", line)
            if m:
                base = int(m.group(1), 16)
            m = re.search(r"\brva=(0x[0-9a-fA-F]+)", line)
            if m:
                rva = int(m.group(1), 16)
                if rva not in rvas:
                    rvas.append(rva)
    return base, rvas


def project_col(m, x, y, z, w, h):
    px = m[0] * x + m[4] * y + m[8] * z + m[12]
    py = m[1] * x + m[5] * y + m[9] * z + m[13]
    pw = m[3] * x + m[7] * y + m[11] * z + m[15]
    if pw != pw or pw <= 1e-6:
        return None
    sx = (px / pw * 0.5 + 0.5) * w
    sy = (0.5 - py / pw * 0.5) * h
    if sx != sx or sy != sy:
        return None
    return sx, sy, pw


def project_row(m, x, y, z, w, h):
    px = m[0] * x + m[1] * y + m[2] * z + m[3]
    py = m[4] * x + m[5] * y + m[6] * z + m[7]
    pw = m[12] * x + m[13] * y + m[14] * z + m[15]
    if pw != pw or pw <= 1e-6:
        return None
    sx = (px / pw * 0.5 + 0.5) * w
    sy = (0.5 - py / pw * 0.5) * h
    if sx != sx or sy != sy:
        return None
    return sx, sy, pw


def boxes_with(m, ents, w, h, project, head_z):
    res = []
    for _pa, v in ents:
        x, y, z = v
        feet = project(m, x, y, z, w, h)
        head = project(m, x, y, z + head_z, w, h)
        if not feet or not head:
            continue
        y1, y0 = feet[1], head[1]
        if not (y1 > y0):
            continue
        bh = y1 - y0
        if bh < 4.0 or bh > 1500.0:
            continue
        res.append((feet, head, bh))
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", default=os.path.join(HERE, "_act_qk_image_live2.txt"))
    ap.add_argument("--out", default=os.path.join(HERE, "_h389_out.txt"))
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

    p("=== h389 projection diag %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
    base, rvas = parse_scan(args.log)
    p("image_pa=%s candidates=%d" % (hex(base) if base else None, len(rvas)))
    if base is None or not rvas:
        p("RESULT: no-candidates")
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

        for rva in rvas:
            b = sess.ph.read(base + rva, 64)
            if not b:
                p("rva=%#010x read fault" % rva)
                continue
            m = struct.unpack("<16f", b)
            if not L.matrix_plausible(m):
                p("rva=%#010x shape=FAIL" % rva)
                continue

            for name, project in (("col", project_col), ("row", project_row)):
                hits = 0
                for _pa, v in ents:
                    x, y, z = v
                    q = project(m, x, y, z, w, h)
                    if not q:
                        continue
                    sx, sy, d = q
                    if 0.0 <= sx <= w and 0.0 <= sy <= h and 1.0 < d < 40000.0:
                        hits += 1
                pos = boxes_with(m, ents, w, h, project, +72.0)
                neg = boxes_with(m, ents, w, h, project, -72.0)
                p("rva=%#010x %s hits=%d/%d boxes+72=%d boxes-72=%d"
                  % (rva, name, hits, len(ents), len(pos), len(neg)))
                sample = pos if pos else neg
                if sample:
                    for feet, head, bh in sample[:3]:
                        p("    feet=(%.1f,%.1f,d=%.1f) head=(%.1f,%.1f,d=%.1f) bh=%.1f"
                          % (feet[0], feet[1], feet[2], head[0], head[1], head[2], bh))

        p("RESULT: diagnostic complete")
        p("VERDICT: PARTIAL - numbers above decide the next qk_live edit")
        return 0
    finally:
        sess.ph.close()
        out.close()


if __name__ == "__main__":
    sys.exit(main())

