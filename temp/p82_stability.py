r"""p82_stability.py -- is the frame's content stable, zero, or churning?

p78 dumped 204 present entries; p81 two minutes later read the same frame as
empty.  If the frame is a freed page the kernel zeroes on free, the dump was
of stale leftovers and everything built on it is stale too.  If it is merely
unstable, the dump needs re-verification on every use.

Reads the frame 4 times 2 s apart and compares each to p78_6c6af.bin: equal
bytes, all-zero, or different with a changed-qword count.  Also counts present
entries per read so drift is visible, not just inferred.
Read-only.
"""
import hashlib
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
import gio  # noqa: E402

OUT = os.path.join(HERE, "_p82_stability.txt")
BIN = os.path.join(HERE, "p78_6c6af.bin")
PA = 0x6C6AF000
PAGE = 0x1000


def main():
    lines = []

    def log(s):
        lines.append(s)

    ref = open(BIN, "rb").read() if os.path.exists(BIN) else None
    log("ref %s present=%s" % ("p78_6c6af.bin" if ref else "MISSING",
                               (sum(1 for v in struct.unpack_from("<512Q", ref or b"")
                                     if v & 1)) if ref else "-"))
    log("ref md5 %s" % (hashlib.md5(ref).hexdigest() if ref else "-"))
    g = gio.Gio()
    try:
        for i in range(4):
            try:
                b = g.read_phys(PA, PAGE)
            except OSError as e:
                log("read %d err %d" % (i, e.args[0] if e.args else -1))
                time.sleep(2)
                continue
            zero = all(c == 0 for c in b)
            pres = sum(1 for v in struct.unpack_from("<512Q", b) if v & 1)
            if ref is None:
                same = "?"
            elif b == ref:
                same = "SAME as p78"
            elif zero:
                same = "ALL ZERO"
            else:
                diff = sum(1 for x, y in zip(struct.unpack_from("<512Q", b),
                                             struct.unpack_from("<512Q", ref))
                           if x != y)
                same = "differs in %d qwords" % diff
            log("read %d md5 %s present=%d %s first=%016x"
                % (i, hashlib.md5(b).hexdigest(), pres, same,
                   struct.unpack_from("<Q", b, 0)[0]))
            time.sleep(2)
    finally:
        g.close()
    zs = sum(1 for ln in lines if "ALL ZERO" in ln or "err" in ln)
    ss = sum(1 for ln in lines if "SAME" in ln)
    if ss == 4:
        log("VERDICT: stable and identical to p78 -- content is trustworthy")
    elif zs == 4:
        log("VERDICT: zeroed now -- p78 caught a page that has since been "
            "freed/zeroed; all table content is stale")
    else:
        log("VERDICT: unstable (%d same, %d zero/err) -- dump must be "
            "re-verified on every use" % (ss, zs))
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
