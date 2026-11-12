r"""_p130.py -- PROBE p130: fresh-cluster autopsy, same-second neighbourhood read.

p129 proved the p127 window was dead: 1 byte changed in 0x8000 over 3 s and none of the three
names were still in it, 3 min after p127.  So a cluster cannot be revisited - the probe has to
sweep, take a cluster the moment it finds it, and dump that neighbourhood immediately.

p127 also mis-scoped its own result: it accepted ANY plausible triple within 0x8000 of a cluster
(that is how it "passed" at 0x7B34 away, deep inside a dead block).  Here the dump is +-0x600,
which is the size of a record if one exists at all.

Two passes 3 s apart.  PASS needs a name in the dump AND a plausible triple inside +-0x100 of it
AND that triple changed between passes.  All three at once, or it is not an entity.

Read-only, gdrv3 only.  Writes temp\_p130_out.txt.
RESULT:/VERDICT: name the variable (R5).  Usage: _p130.py [--secs=90] [--wait=N]
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import gio
import dumplive as dl

OUT = os.path.join(HERE, "_p130_out.txt")
NEEDLES = ["kern30120", "spanner1981", "Gen X Gaming"]
CHUNK = 0x100000
BAND = 0x600
GAP = 3


def say(s):
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(s + "\n")


def pl(v):
    return v == v and 1e-6 < abs(v) < 1e7


def near3(hits):
    """first address where >=3 names sit inside 0x100 - the tightest thing we can trust"""
    for a, _n in hits:
        got = {n for b, n in hits if abs(b - a) <= 0x100}
        if len(got) >= 3:
            return a
    return None


def dump(g, pa):
    try:
        b = dl.retry_phys(g, pa - BAND, BAND * 2 + 16, tries=3)
    except Exception:                                          # noqa: BLE001
        return None
    return b if b and len(b) >= BAND * 2 else None


def show(tag, pa, b):
    say("  %s  %#x +-0x%x  names=%s" % (tag, pa, BAND,
        sorted(n for n in NEEDLES if n.encode("ascii") in b) or "NONE"))
    for o in range(0, len(b) - 3, 4):
        x, y, z = struct.unpack("<fff", b[o:min(o + 12, len(b))] + b"\0" * 12)[:3]
        if not (pl(x) and pl(y) and pl(z)):
            continue
        if abs(x) > 12000 or abs(y) > 4000 or abs(z) > 12000:
            continue
        if abs(x) > 250 or abs(z) > 250:
            say("    trip %+#x  %.2f %.2f %.2f" % (o - BAND, x, y, z))


def main():
    secs = 90
    wait = 0
    for a in sys.argv:
        if a.startswith("--secs="):
            secs = int(a.split("=", 1)[1])
        elif a.startswith("--wait="):
            wait = int(a.split("=", 1)[1])
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" --secs=%d --wait=%d'
                            % (os.path.abspath(__file__), secs, wait)))
        return 0
    open(OUT, "w").close()

    t0 = time.time()
    say("=== p130 fresh-cluster autopsy %s ===" % time.strftime("%H:%M:%S"))
    pid = dl.find_pid()
    if pid is None and wait > 0:
        say("waiting up to %ds" % wait)
        while pid is None and time.time() - t0 < wait:
            time.sleep(3)
            pid = dl.find_pid()
    say("game_pid=%s" % pid)
    if pid is None:
        say("RESULT: game_pid=none")
        say("VERDICT: PARTIAL - game not running (R9)")
        return 3
    try:
        g = gio.Gio(chunk=CHUNK)
    except OSError as e:
        say("gio: %s" % e)
        return 2

    pats = {n: n.encode("ascii") for n in NEEDLES}
    ranges, rnote = dl.usable_ranges(g.ram_top, 0x1000, None)
    say("ranges=%d note=%s ram_top=%#x" % (len(ranges), rnote, g.ram_top))
    hits, driver = [], 0
    anchor = None
    for rlo, rhi in ranges:
        pa = (rlo + 7) & ~7
        while pa + CHUNK <= rhi and time.time() - t0 < secs:
            try:
                blk = dl.retry_phys(g, pa, CHUNK, tries=1)
            except OSError:
                pa += 0x1000
                continue
            for n, p in pats.items():
                i = blk.find(p)
                while i >= 0:
                    hits.append((pa + i, n))
                    i = blk.find(p, i + 1)
            driver += CHUNK
            if hits:
                anchor = near3(sorted(hits))
                if anchor:
                    break
            pa += CHUNK
        if anchor:
            break
    say("swept=%#x hits=%d anchor=%s (%.0fs)"
        % (driver, len(hits), anchor and hex(anchor), time.time() - t0))
    if anchor is None:
        say("RESULT: hits=%d anchor=none" % len(hits))
        say("VERDICT: FAIL - no address carries all three names inside 0x100")
        return 1

    a = dump(g, anchor)
    say("pass1 at %s" % time.strftime("%H:%M:%S"))
    if a is None:
        say("VERDICT: FAIL - anchor unreadable")
        return 1
    show("p1", anchor, a)
    time.sleep(GAP)
    b = dump(g, anchor)
    say("pass2 at %s" % time.strftime("%H:%M:%S"))
    if b is None:
        say("VERDICT: FAIL - anchor lost between passes")
        return 1
    show("p2", anchor, b)

    names = [n for n in NEEDLES if n.encode("ascii") in a]
    chg = [i for i in range(0, min(len(a), len(b)) - 3, 4) if a[i:i + 4] != b[i:i + 4]]
    say("names_in_band=%d changed_fields=%d" % (len(names), len(chg)))
    band = [i for i in chg if abs(i - BAND) <= 0x100]
    for i in chg[:20]:
        x, y = struct.unpack("<ff", a[i:i + 4] + b[i:i + 4])
        say("  chg %+#x %.4f -> %.4f" % (i - BAND, x, y))

    say("RESULT: names=%d changed=%d changed_within_0x100=%d"
        % (len(names), len(chg), len(band)))
    if names and band:
        say("VERDICT: PASS - name and live field within 0x100: candidate delta at %#x"
            % anchor)
    elif names:
        say("VERDICT: PARTIAL - name present, band live printing but nothing moved in +-0x100")
    else:
        say("VERDICT: FAIL - anchor dead within seconds")
    return 0


if __name__ == "__main__":
    sys.exit(main())
