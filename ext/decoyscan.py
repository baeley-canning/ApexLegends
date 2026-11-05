"""decoyscan.py -- find EAC decoy EPROCESS copies by their 0xC0 phase.

The p44d decoy layout: the fake object base sits at page offset 0xC0, so its
pid dword lives at +0x290, its name at +0x3F8 and its LIST_ENTRY pair at
+0x298.  shape_at() never probes 0xC0 pages, so basehunt cannot log the trio
itself -- this scan anchors on the pid dword and tests the fixed decoy phase:
type 3, r5apex name, and a *pair* whose lanes both equal 0x298.  The pair
values are the decoy's flink/blink in the frame space (0xFFFFA401...), i.e.
the DUMP_FL/DUMP_BL inputs a later accept pass needs; the base PA is DUMP_LINK.

Read-only, device open only.  1 MiB chunks, faults rescued at 4 KiB.
Usage: decoyscan.py --pid=0x5c84 [--lo=0x140000000 --hi=0x1b7ea1000] [--want=3]
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402
import dumplive as dl  # noqa: E402

ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_OUT", "p44f_decoy.txt"))
PROG = os.path.join(ROOT, "_ritual", os.environ.get("DUMP_PROG", "p44f_dprog.txt"))
DEC_OFF = 0xC0                 # object base phase (p44d measured)
PID_AT = DEC_OFF + 0x1D0       # 0x290
NAME_AT = DEC_OFF + 0x338      # 0x3F8
PAIR_AT = DEC_OFF + 0x1D8      # 0x298
WANT_DEF = 3

LOG = []


def log(s):
    LOG.append(s)
    print(s)


def prog(s):
    try:
        with open(PROG, "a", encoding="utf-8") as f:
            f.write("%s  %s\n" % (time.strftime("%H:%M:%S"), s))
            f.flush()
            os.fsync(f.fileno())
    except OSError:
        pass


def wr(code, verdict):
    log("VERDICT: %s" % verdict)
    open(OUT, "w", encoding="utf-8").write("\n".join(LOG) + "\n")
    return code


def test(chunk, i):
    """Chunk offset of the pid dword -> (fl, bl) if the 0xC0 decoy checks pass."""
    base = i - PID_AT
    if base < 0 or base + NAME_AT + 15 - DEC_OFF > len(chunk):
        return None
    if chunk[base] != 3:
        return None
    nm = chunk[base + 0x338:base + 0x338 + 15].split(b"\x00", 1)[0]
    if not nm.startswith(b"r5apex") or not all(0x20 <= c < 0x7F for c in nm):
        return None
    fl, bl = struct.unpack_from("<QQ", chunk, base + 0x1D8)
    if fl >> 48 != 0xFFFF or bl >> 48 != 0xFFFF:
        return None
    # Stored lanes point at neighbours (0x258-phase EPROCESS nodes) or at other
    # trio members (0x298); the decoy's *own* lane is only on inbound links.
    if (fl & 0xFFF) not in (0x258, 0x298) or (bl & 0xFFF) not in (0x258, 0x298):
        return None
    return fl, bl


def main():
    pid = None
    lo, hi, want = 0x140000000, 0x1B7EA1000, WANT_DEF
    for a in sys.argv[1:]:
        if a.startswith("--pid="):
            pid = int(a.split("=", 1)[1], 0)
        elif a.startswith("--lo="):
            lo = int(a.split("=", 1)[1], 0)
        elif a.startswith("--hi="):
            hi = int(a.split("=", 1)[1], 0)
        elif a.startswith("--want="):
            want = int(a.split("=", 1)[1], 0)
    if not pid:
        return wr(4, "NO_PID")
    pat = struct.pack("<I", pid)
    log("decoyscan %s pid=%#x %#x..%#x"
        % (time.strftime("%Y-%m-%d %H:%M:%S"), pid, lo, hi))
    try:
        g = gio.Gio(chunk=dl.SCAN_CHUNK)
        top = g.ram_top
    except OSError as e:
        log("FATAL: %s" % e)
        return wr(2, "FATAL no transport")
    hi = min(hi, top)
    found, seen = [], set()
    pa, step, chunks = lo, 0x100000, 0
    t0 = time.perf_counter()
    while pa < hi and len(found) < want:
        n = min(step, hi - pa)
        try:
            chunk = g.read_phys(pa, n)
        except OSError:
            chunk = None
        spans = [(0, chunk, n)] if chunk is not None else ()
        if chunk is None:
            spans = []
            for sub in range(0, n, 0x1000):
                sn = min(0x1000, n - sub)
                try:
                    spans.append((sub, g.read_phys(pa + sub, sn), sn))
                except OSError:
                    pass
        for sub, blk, ln in spans:
            off = 0
            while True:
                i = blk.find(pat, off)
                if i < 0 or i & 7 != 0:
                    if i < 0:
                        break
                    off = i + 1
                    continue
                off = i + 1
                r = test(blk, i)
                if r is None:
                    continue
                base = pa + sub + i - PID_AT
                if base in seen:
                    continue
                seen.add(base)
                found.append(base)
                log("DECOY pa=%#x fl=%#x bl=%#x pid=%#x name=%r"
                    % (base, r[0], r[1], pid,
                       blk[i + 0xA8:i + 0xA8 + 15].split(b"\x00", 1)[0]))
                prog("DECOY pa=%#x n=%d" % (base, len(found)))
        chunks += 1
        if chunks % 64 == 0:
            prog("CKPT pa=%#x found=%d %.1fs" % (pa, len(found),
                                                 time.perf_counter() - t0))
        pa += n
    g.close()
    log("%d decoys, %d MiB, %.1fs" % (len(found), (pa - lo) >> 20,
                                      time.perf_counter() - t0))
    if not found:
        return wr(0, "NO_DECOY")
    return wr(0, "FOUND n=%d first=%#x" % (len(found), found[0]))


if __name__ == "__main__":
    sys.exit(main())
