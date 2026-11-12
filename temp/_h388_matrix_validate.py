r"""h388 -- validate the qk_image matrix candidates against the live census.

Input: a fresh `qk_image --data --watch` log that lists the current image and
the 16-float candidate windows it found in `.data`.  This probe does not rescan
the image; it re-reads only those candidate windows live, projects the proven
census records through each one, and if a candidate is coherent, caches it in
`temp\qk_offsets.txt` for `qk_live.py`.

Read-only: no driver/service/CI/boot state is touched.  Every physical read goes
through `qk_live.Phys`, which guards each address with the RAM map's interval
set (R10).  A candidate that cannot project the census is not promoted, and a
failed probe leaves `qk_offsets.txt` unchanged.
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
    """(image_pa, [candidate rvas]) from a qk_image --data --watch log."""
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


def pe_ok(ph, base):
    """Cheap MZ/PE/size check on the image the scan log claims is live."""
    b = ph.read(base, 0x400)
    if not b or len(b) < 0x200 or b[:2] != b"MZ":
        return False
    lf = struct.unpack_from("<I", b, 0x3C)[0]
    if not (0x40 <= lf <= 0x3F0) or b[lf:lf + 4] != b"PE\x00\x00":
        return False
    if struct.unpack_from("<H", b, lf + 4)[0] != 0x8664:
        return False
    size = struct.unpack_from("<I", b, lf + 0x50)[0]
    return 0x0DF00000 <= size <= 0x0E100000


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", default=os.path.join(HERE, "_act_qk_image_live2.txt"))
    ap.add_argument("--out", default=os.path.join(HERE, "_h388_out.txt"))
    ap.add_argument("--no-elevate", action="store_true")
    args = ap.parse_args()

    out = open(args.out, "w", encoding="utf-8", newline="\n")

    def p(s=""):
        print(s, flush=True)
        out.write(s + "\n")
        out.flush()

    p("=== h388 matrix validate %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
    p("log=%s" % args.log)
    if not os.path.isfile(args.log):
        p("RESULT: no-scan-log")
        p("VERDICT: BLOCKED / PARTIAL (SKIPPED physical gates) - qk_image log missing")
        out.close()
        return 2

    base, rvas = parse_scan(args.log)
    p("parsed image_pa=%s candidate_rvas=%d" % (hex(base) if base else None, len(rvas)))
    if base is None or not rvas:
        p("RESULT: no-candidates")
        p("VERDICT: BLOCKED / PARTIAL (SKIPPED physical gates) - log has no image/candidates")
        out.close()
        return 2

    pid = dl.find_pid()
    p("G0 game pid=%s alive=%s elevated=%s"
      % (pid, bool(pid and dl.pid_alive(pid)), dl.elevation()))
    if not pid or not dl.pid_alive(pid):
        p("RESULT: game-not-running")
        p("VERDICT: PARTIAL (SKIPPED physical gates, R9) - game not running")
        out.close()
        return 3

    sess = None
    try:
        sess = L.Session(cap=28, base=base, rva=0)
    except OSError as e:
        p("gio: %s" % e)
        p("VERDICT: FAIL - could not open the physical read transport")
        out.close()
        return 2

    try:
        rect = L.game_rect(pid) or L.screen_rect()
        w, h = rect[2] - rect[0], rect[3] - rect[1]
        p("window rect=%s (%dx%d)" % (rect, w, h))

        g1 = pe_ok(sess.ph, base)
        p("G1 image_pe=%s" % ("PASS" if g1 else "FAIL"))
        if not g1:
            p("RESULT: bad-image")
            p("VERDICT: FAIL - image_pa from the scan log is not a live PE image")
            return 1

        ents = sess.prime()
        p("G3 census seeds=%d positions=%d dropped=%d reads=%d"
          % (sess.seed_total, len(ents), sess.dropped, sess.ph.reads))
        if not ents:
            p("RESULT: no-positions")
            p("VERDICT: FAIL - no census record holds a position")
            return 1

        best = None
        for rva in rvas:
            b = sess.ph.read(base + rva, 64)
            if not b:
                p("  rva=%#010x read fault" % rva)
                continue
            m = struct.unpack("<16f", b)
            if not L.matrix_plausible(m):
                p("  rva=%#010x shape=FAIL" % rva)
                continue
            hits = L.score_vp(m, ents, w, h)
            boxes = L.boxes_for(m, ents, w, h)
            p("  rva=%#010x shape=PASS hits=%d/%d boxes=%d"
              % (rva, hits, len(ents), len(boxes)))
            if hits >= 3 and len(boxes) >= 3 and (best is None or hits > best[1]):
                best = (rva, hits, len(boxes), m)

        g2 = best is not None
        p("G2 candidate_matrix=%s" % ("PASS" if g2 else "FAIL"))

        if best is None:
            p("RESULT: no-coherent-matrix")
            p("VERDICT: PARTIAL - candidates read but none projects the census")
            return 4

        rva, hits, boxes, m0 = best
        time.sleep(0.3)
        b2 = sess.ph.read(base + rva, 64)
        if not b2:
            p("G5 re-read=FAIL")
            p("RESULT: candidate-lost")
            p("VERDICT: PARTIAL - best candidate could not be re-read")
            return 4
        m1 = struct.unpack("<16f", b2)
        if not L.matrix_plausible(m1):
            p("G5 re-read=FAIL (second sample failed the shape gate)")
            p("RESULT: torn-second-sample")
            p("VERDICT: PARTIAL - candidate changed to a non-matrix between samples")
            return 4
        delta = max(abs(a - b) for a, b in zip(m0, m1))
        p("G5 re-read=PASS delta=%.6g (%s)"
          % (delta, "static" if delta < 1e-6 else "moved"))

        g4 = hits >= 3 and boxes >= 3
        p("G4 projection=%s hits=%d boxes=%d" % ("PASS" if g4 else "FAIL", hits, boxes))
        if not g4:
            p("RESULT: weak-projection")
            p("VERDICT: PARTIAL - candidate projects too few records to trust")
            return 4

        with open(os.path.join(ROOT, "temp", "qk_offsets.txt"), "w", encoding="utf-8") as f:
            f.write("image_pa=0x%X\nvp_rva=0x%X\n" % (base, rva))
        p("CACHED temp\\qk_offsets.txt image_pa=%#x vp_rva=%#x" % (base, rva))
        p("RESULT: vp_rva=%#x hits=%d/%d boxes=%d delta=%.6g"
          % (rva, hits, len(ents), boxes, delta))
        p("VERDICT: PASS - candidate projects the live census; qk_live may draw")
        return 0
    finally:
        try:
            sess.ph.close()
        except Exception:
            pass
        out.close()


if __name__ == "__main__":
    sys.exit(main())


