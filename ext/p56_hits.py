"""p56_hits.py -- raw needle hits with context, no header filter (debug for p56_diff).

Usage: p56_hits.py --needle=text --lo=0x.. --hi=0x.. [--out=path]
Read-only, elevated.
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402

CHUNK = 0x10000
PAGE = gio.PAGE
SPLIT = True
LOG = []


def log(s):
    LOG.append(s)
    print(s)


def scan_range(g, pa, size, needle, sig, emit):
    """Read [pa, pa+size) and emit hits; on 1450 bisect instead of giving up.

    A free page anywhere inside a chunk makes the driver's MmMapIoSpace fail for
    the whole chunk, so a single hole would blind up to 16 good pages.  Bisect
    down to one page so holes only cost their own page.
    """
    try:
        blk = g.read_phys(pa, size)
    except OSError:
        if size <= PAGE or not SPLIT:
            emit(pa, None)
            return 0
        half = size >> 1
        a = scan_range(g, pa + half, half, needle, sig, emit)
        b = scan_range(g, pa, half, needle, sig, emit)
        return a + b
    if blk is None:
        return 1
    emit(pa, blk)
    return 1


def main(argv):
    needle, lo, hi = None, 0x626d00000, 0x62700000
    out = os.path.join(os.path.dirname(HERE), "temp", "p56_hits.txt")
    sig = split = trace = utf16 = False
    max_s = 60.0
    for a in argv:
        if a.startswith("--needle="):
            needle = a[9:].encode()
        elif a.startswith("--lo="):
            lo = int(a[5:], 16)
        elif a.startswith("--hi="):
            hi = int(a[5:], 16)
        elif a.startswith("--out="):
            out = a[6:]
        elif a == "--sig":
            sig = True
        elif a == "--trace":
            trace = True
        elif a == "--no-split":
            split = False
        elif a == "--utf16":
            utf16 = True
        elif a.startswith("--max_s="):
            max_s = float(a[8:])
    if not needle:
        print("usage: p56_hits.py --needle=text --lo=0x.. --hi=0x.. "
              "[--sig] [--trace] [--no-split] [--utf16] [--max_s=60] --out=path")
        return 2
    if utf16:
        needle = needle.decode().encode("utf-16-le")
    global SPLIT
    SPLIT = split
    t0 = time.time()
    h = open(out, "w", encoding="utf-8")
    LOG.clear()

    def log(s):
        LOG.append(s)
        h.write(s + "\n")
        h.flush()

    log("# p56_hits %s needle=%r %#x-%#x sig=%d trace=%d split=%d max_s=%.0f"
        % (time.strftime("%Y-%m-%d %H:%M:%S"), needle, lo, hi, sig, trace, split,
           max_s))
    g = gio.Gio()
    hits = chunks = faults = 0

    def emit(pa, blk):
        nonlocal hits, chunks, faults
        if blk is None:
            faults += 1
            return
        chunks += 1
        i = blk.find(needle)
        while i >= 0:
            pre = blk[max(0, i - 0x30):i]
            post = blk[i + len(needle):i + len(needle) + 0x40]
            ok = (pre[-4:] == struct.pack("<I", len(needle))
                  and blk[i + len(needle):i + len(needle) + 1] == b"\0")
            if not sig or ok:
                hits += 1
                log("HIT%s addr=%#x" % (" sig" if ok else "", pa + i))
                log("  pre=%s" % pre.hex())
                log("  post=%s" % post.hex())
            i = blk.find(needle, i + 1)

    pa = hi - CHUNK
    while pa >= lo and time.time() - t0 < max_s:
        if trace:
            log("SCAN pa=%#x t=%.1f" % (pa, time.time() - t0))
        scan_range(g, pa, min(CHUNK, hi - pa), needle, sig, emit)
        pa -= CHUNK
    g.close()
    log("hits=%d chunks=%d faults=%d secs=%.1f stop=%#x"
        % (hits, chunks, faults, time.time() - t0, pa))
    h.close()
    return 0 if hits else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
