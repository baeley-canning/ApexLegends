r"""p71_watch.py -- passive continuous memory watcher: no countdown, no shots.

One anchor scan, then long unattended sweeps of the hit pages diffing every
dword.  The player just plays; each sweep logs what changed and where relative
to each name hit.  Offline analysis turns churn into the player struct.

Usage: python ext\p71_watch.py [--needle=kern30120] [--run=240] [--pages=2]
       [--cap=6000] [--last=temp\p64_seed.txt] [--min=0.8]
       [--out=temp\p71_out.txt] [--stop=temp\p71_stop.txt]

Beep protocol: one 0.9 s tone = LIVE (start playing), a soft tick every 45 s
while alive, low tone on exit.  Stop early by creating the stop file.
Read-only: nothing here writes memory.
"""
import os
import struct
import sys
import time

try:
    import winsound
except ImportError:                     # non-Windows fallback
    winsound = None


def beep(freq, ms):
    if winsound:
        try:
            winsound.Beep(freq, ms)
        except RuntimeError:
            pass


HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gio  # noqa: E402
import p56_hits  # noqa: E402

ROOT = os.path.dirname(HERE)
CHUNK = 0x10000
PAGE = gio.PAGE
FULL = (0x400000000, 0x780000000)
SPAN = 0x1000000      # +-16 MiB window from the last anchor
PAGES = 2             # +-pages around each hit
CAP = 6000            # hard page ceiling (1121 hits * 5 = 5605 at defaults)
MIN_EVERY = 0.8       # seconds between sweep starts
MAX_LPS = 2500        # log lines per sweep before summarizing the rest
RUN = 240.0
STRIKES = 2           # cold sweeps before re-anchoring
MAX_REANCHOR = 3
NEAR = 17             # dwords sampled either side of a hit at anchor time


class Out(object):
    def __init__(self, path):
        self.h = open(path, "w", encoding="utf-8")

    def __call__(self, s):
        print(s)
        self.h.write(s + "\n")
        self.h.flush()

    def close(self):
        self.h.close()


def window_from_last(path):
    pages = []
    if not path or not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("HIT "):
                pages.append(int(line.split("addr=")[1], 16) & ~0xFFF)
    if not pages:
        return None
    lo, hi = min(pages) - SPAN, max(pages) + SPAN
    if hi - lo > 0x60000000:       # 1.5 GiB: a full-band hit set still seeds
        return None
    return max(FULL[0], lo), min(FULL[1], hi)


def scan(g, lo, hi, needle, out, budget, label="SCAN"):
    hits = []
    if isinstance(needle, str):         # callers pass the raw CLI string
        needle = needle.encode()
    t0 = time.time()
    faults = 0

    def emit(pa, blk):
        nonlocal faults
        if blk is None:
            faults += 1
            return
        i = blk.find(needle)
        while i >= 0:
            hits.append(pa + i)
            i = blk.find(needle, i + 1)

    pa = hi - CHUNK
    while pa >= lo and time.time() - t0 < budget:
        p56_hits.scan_range(g, pa, min(CHUNK, hi - pa), needle, False, emit)
        pa -= CHUNK
    stopped = "covered" if pa < lo else "budget"
    out("%s %#x-%#x hits=%d faults=%d t=%.1fs stopped=%s" % (
        label, lo, hi, len(hits), faults, time.time() - t0, stopped))
    return hits


def build_pages(hits):
    """page -> (hit id, signed distance).  Nearest hit wins; every hit keeps
    at least its own page so no hit can be dropped by a neighbour."""
    owner = {}
    for i, a in enumerate(hits):
        p = a & ~0xFFF
        for k in range(-PAGES, PAGES + 1):
            q = p + k * PAGE
            if q < PAGE:
                continue
            d = abs(q - p)
            if q not in owner or d < abs(owner[q][1]):
                owner[q] = (i, q - p)
    pages = sorted(owner)
    if len(pages) > CAP:
        keep = pages[:CAP]
        owner = {p: owner[p] for p in keep}
        pages = keep
    return pages, owner


def anchor(g, needle, last, out):
    hits = []
    win = window_from_last(last)
    if win:
        out("window=%#x-%#x (from %s)" % (win[0], win[1], os.path.basename(last or "")))
        hits = scan(g, win[0], win[1], needle, out, 25.0, "WSCAN")
        if len(hits) < 25:
            out("window weak (%d) -> full band" % len(hits))
            hits += scan(g, FULL[0], FULL[1], needle, out, 90.0)
    if not hits:
        out("window cold -> full band")
        hits = scan(g, FULL[0], FULL[1], needle, out, 90.0)
    return sorted(set(hits))


def sample(g, hits, out):
    """Static neighbourhood dump -- offset work later needs these."""
    for i, a in enumerate(hits[:40]):
        p = a & ~0xFFF
        try:
            buf = g.read_phys(p, PAGE)
        except OSError:
            out("NEAR %d %#011x fault" % (i, a))
            continue
        off = a & 0xFFF
        lo = max(0, off - NEAR * 4)
        hi = min(PAGE - 4, off + NEAR * 4)
        lane = []
        for o in range(lo, hi + 1, 4):
            v = struct.unpack_from("<I", buf, o)[0]
            f = struct.unpack_from("<f", buf, o)[0]
            kind = "~" if (f == f and 1e-6 < abs(f) < 1e6) else " "
            lane.append("%s%+#x:%08x%s" % (">" if o == off else "|", o - off, v, kind))
        out("NEAR %d %#011x %s" % (i, a, "".join(lane)))


def main(argv):
    needle = "kern30120"
    out_path = os.path.join(ROOT, "temp", "p71_out.txt")
    stop_path = os.path.join(ROOT, "temp", "p71_stop.txt")
    last = os.path.join(ROOT, "temp", "p64_seed.txt")
    for a in argv:
        if a.startswith("--needle="):
            needle = a[9:]
        elif a.startswith("--run="):
            globals()["RUN"] = float(a[6:])
        elif a.startswith("--pages="):
            globals()["PAGES"] = int(a[8:])
        elif a.startswith("--cap="):
            globals()["CAP"] = int(a[6:])
        elif a.startswith("--min="):
            globals()["MIN_EVERY"] = float(a[6:])
        elif a.startswith("--maxlps="):
            globals()["MAX_LPS"] = int(a[9:])
        elif a.startswith("--out="):
            out_path = a[6:]
        elif a.startswith("--stop="):
            stop_path = a[7:]
        elif a.startswith("--last="):
            last = a[7:]
    nb = needle.encode()

    out = Out(out_path)
    out("# p71_watch %s needle=%r pages=%d cap=%d run=%.0f" % (
        time.strftime("%Y-%m-%d %H:%M:%S"), nb, PAGES, CAP, RUN))
    if os.path.exists(stop_path):
        os.remove(stop_path)
    g = gio.Gio()
    try:
        t_start = time.time()
        hits = anchor(g, needle, last, out)
        if not hits:
            out("VERDICT no-anchor")
            beep(400, 600)
            return 3
        out("ANCHOR hits=%d" % len(hits))
        with open(os.path.join(ROOT, "temp", "p71_hits.txt"), "w") as f:
            for i, a in enumerate(hits):
                f.write("HIT %d addr=%#011x\n" % (i, a))
        sample(g, hits, out)

        pages, owner = build_pages(hits)
        out("PAGES n=%d" % len(pages))
        beep(1200, 900)                 # LIVE: play, come back in ~4 min
        t_watch = time.time()
        prev = {}
        churn = [0] * len(hits)
        addrs = {}                      # addr -> change count, final table
        reanchors = strikes = 0
        k = 0
        tick_at = time.time() + 45.0
        while time.time() - t_watch < RUN:
            if os.path.exists(stop_path):
                out("STOP file")
                break
            time.sleep(MIN_EVERY)
            k += 1
            t0 = time.time()
            ok = 0
            logs = []
            cut = 0
            for p in pages:
                try:
                    buf = g.read_phys(p, PAGE)
                except OSError:
                    prev[p] = None
                    continue
                ok += 1
                old = prev.get(p)
                prev[p] = buf
                if old is None or old == buf:      # first look is not a diff
                    continue
                i_hit, dist = owner[p]
                for off in range(0, PAGE - 3, 4):
                    nv = struct.unpack_from("<I", buf, off)[0]
                    ov = struct.unpack_from("<I", old, off)[0] if off + 4 <= len(old) else 0
                    if nv == ov:
                        continue
                    a = p + off
                    churn[i_hit] += 1
                    addrs[a] = addrs.get(a, 0) + 1
                    if len(logs) < MAX_LPS:
                        logs.append("C %d d=%+#x %#011x %d->%d" % (i_hit, dist + off, a, ov, nv))
                    else:
                        cut += 1
            # idle sweeps stay out of the file; every 20th still marks liveness
            if logs or k % 20 == 0:
                out("SWEEP %d t=%s s=%dms pages=%d/%d churn=%d%s" % (
                    k, time.strftime("%H:%M:%S"), int((time.time() - t0) * 1000),
                    ok, len(pages), len(logs) + cut, "" if not cut else " (+%d cut)" % cut))
            for line in logs:
                out(line)
            if time.time() >= tick_at:
                tick_at = time.time() + 45.0
                beep(1500, 50)
            if ok < len(pages) * 0.4 and len(pages) > 20:
                strikes += 1
                out("COLD sweep=%d ok=%d/%d strike=%d" % (k, ok, len(pages), strikes))
                if strikes >= STRIKES:
                    if reanchors >= MAX_REANCHOR:
                        out("VERDICT cold-out")
                        break
                    reanchors += 1
                    out("REANCHOR %d" % reanchors)
                    beep(700, 300)
                    nh = sorted(set(scan(g, FULL[0], FULL[1], nb, out, 90.0, "RSCAN")))
                    if nh:
                        hits = nh
                        pages, owner = build_pages(hits)
                        churn = [0] * len(hits)
                        prev = {}
                        out("REANCHOR hits=%d pages=%d" % (len(hits), len(pages)))
                    strikes = 0
            else:
                strikes = 0

        out("SWEEPS %d secs=%.0f daddrs=%d" % (k, time.time() - t_watch, len(addrs)))
        out("TCHURN")
        for i in sorted(range(len(hits)), key=lambda i: -churn[i])[:40]:
            out("T %d addr=%#011x churn=%d" % (i, hits[i], churn[i]))
        out("TADDR")
        for a in sorted(addrs, key=lambda a: -addrs[a])[:80]:
            p = a & ~0xFFF
            i_hit, dist = owner.get(p, (-1, 0))
            out("A %#011x n=%d hit=%d d=%+#x" % (a, addrs[a], i_hit, dist + (a - p)))
        out("VERDICT watched")
        beep(600, 400)
        return 0
    finally:
        g.close()
        out.close()


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        print("INT")
