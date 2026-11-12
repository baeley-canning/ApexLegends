r"""h390 -- dump the two h388 candidate matrices and their first projections.

h389 proved the candidates are column-convention and put 26/28 records on
screen, but still yield zero boxes for both +72 and -72 head offsets.  This
probe prints the 16 floats of each candidate and the first few feet/head screen
coordinates so the failure is visible as numbers instead of a boolean.
"""
import argparse
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", default=os.path.join(HERE, "_act_qk_image_live2.txt"))
    ap.add_argument("--out", default=os.path.join(HERE, "_h390_out.txt"))
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

    p("=== h390 matrix dump %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
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

            p("rva=%#010x matrix:" % rva)
            for row in range(4):
                p("  [%d] %s" % (row, "  ".join("%12.6f" % v for v in m[row * 4:row * 4 + 4])))

            p("  first 5 projections (feet | head +72 | head -72):")
            for idx, (_pa, v) in enumerate(ents[:5]):
                x, y, z = v
                feet = L.project(m, x, y, z, w, h)
                headp = L.project(m, x, y, z + 72.0, w, h)
                headn = L.project(m, x, y, z - 72.0, w, h)
                p("    %d feet=%s head+=%s head-=%s"
                  % (idx,
                     ("(%.1f,%.1f,d=%.1f)" % feet) if feet else "None",
                     ("(%.1f,%.1f,d=%.1f)" % headp) if headp else "None",
                     ("(%.1f,%.1f,d=%.1f)" % headn) if headn else "None"))

        p("RESULT: dump complete")
        p("VERDICT: PARTIAL - numbers above decide the next qk_live edit")
        return 0
    finally:
        sess.ph.close()
        out.close()


if __name__ == "__main__":
    sys.exit(main())
