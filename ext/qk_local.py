r"""qk_local.py -- find the LOCAL PLAYER by its own health drop (Octane stim).

Why this shape: ~25k "health-looking" clusters exist in the range (geometry, UI,
materials), so picking one by density is a lottery.  A stim is a KNOWN event:
health 100 -> ~80 within a second.  Re-reading the 100.0f candidates after a stim
and keeping only the ones that moved turns 68k candidates into a handful - and those
are the player's own health field.

Then the same run dumps that neighbourhood twice (stand still / run) and prints the
floats that CHANGED, which is where the position lives.

Usage: qk_local.py [--out=FILE] [--sit=6] [--move=4]
Exit: 0 found, 8 nothing moved.
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gio            # noqa: E402
import dumplive as dl  # noqa: E402

try:
    import winsound
except ImportError:
    winsound = None

ROOT = os.path.dirname(HERE)
TMP = os.path.join(ROOT, "temp")
F100 = b"\x00\x00\xc8\x42"
LOG = []
OUT = None


def beep(freq, ms):
    if winsound:
        try:
            winsound.Beep(freq, ms)
        except RuntimeError:
            pass


def set_out(p):
    global OUT
    OUT = os.path.abspath(p) if p else None
    if OUT:
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("")


def out(s):
    line = str(s)
    print(line)
    LOG.append(line)
    if OUT:
        with open(OUT, "a", encoding="utf-8") as f:
            f.write(line + "\n")


def arg(name, default=None, cast=str):
    for i, a in enumerate(sys.argv):
        if a == "--" + name and i + 1 < len(sys.argv):
            return cast(sys.argv[i + 1])
        if a.startswith("--" + name + "="):
            return cast(a.split("=", 1)[1])
    return default


def scan_100(g, ranges):
    """Physical addresses of aligned 100.0f, block read with page fallback."""
    hits = []
    n = 0
    for rlo, rhi in ranges:
        pa = (rlo + 7) & ~7
        while pa + 0x10000 <= rhi:
            pa += 0x10000
            try:
                blk = dl.retry_phys(g, pa - 0x10000, 0x10000, tries=1)
                base = pa - 0x10000
            except OSError:
                base = pa - 0x10000
                for off in range(0, 0x10000, 0x1000):
                    try:
                        sub = dl.retry_phys(g, base + off, 0x1000, tries=1)
                    except OSError:
                        continue
                    i = sub.find(F100)
                    while i >= 0:
                        if (i & 3) == 0:
                            hits.append(base + off + i)
                        i = sub.find(F100, i + 1)
                continue
            n += 1
            i = blk.find(F100)
            while i >= 0:
                if (i & 3) == 0:
                    hits.append(base + i)
                i = blk.find(F100, i + 1)

def main():
    out_path = arg("out", os.path.join(TMP, "qk_local_%s.txt"
                                      % time.strftime("%Y%m%d_%H%M%S")))
    set_out(out_path)
    if not dl.elevation() and ("--no-elevate" not in sys.argv):
        cmd = " ".join('"%s"' % a if " " in a else a for a in sys.argv) + " --no-elevate"
        out("not elevated - relaunching")
        out(dl.run_elevated(cmd))
        return 0

    out("===== qk_local (health-drop finder: stim identifies the local player) =====")
    out("out=%s" % out_path)
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        out("gio open failed: %s" % e)
        return 2

    try:
        ranges, note = dl.usable_ranges(g.ram_top, None, None)
        out("ranges=%d (%s)" % (len(ranges), note))
        hits = scan_100(g, ranges)

        out("")
        out("  *** STIM NOW (hold it, 3-4 stims) ***")
        beep(1400, 250)
        time.sleep(arg("sit", 6, lambda s: float(s)))

        moved = []
        for a in hits:
            try:
                b = dl.retry_phys(g, a, 4, tries=1)
            except OSError:
                continue
            v = struct.unpack("<f", b)[0]
            if v != 100.0:
                moved.append((a, v))
        beep(900, 200)
        out("  candidates that changed: %d" % len(moved))
        for a, v in moved[:40]:
            out("    %#012x  now %.3f" % (a, v))
        if not moved:
            out("RESULT: none-changed")
            out("VERDICT: PARTIAL - no 100.0f candidate moved during the stim")
            return 8

        targets = [a for a, _ in moved[:3]]
        snaps = {}
        out("")
        out("  *** STAND STILL for 2 s ***")
        time.sleep(2)
        for a in targets:
            try:
                snaps[a] = dl.retry_phys(g, a - 0x300, 0x800, tries=3)
            except OSError:
                snaps[a] = None
        out("  *** NOW RUN IN A CIRCLE for %ss ***" % arg("move", 4, lambda s: float(s)))
        beep(1200, 200)
        time.sleep(arg("move", 4, lambda s: float(s)))
        beep(700, 200)
        for a in targets:
            before = snaps.get(a)
            if not before:
                continue
            try:
                after = dl.retry_phys(g, a - 0x300, 0x800, tries=3)
            except OSError:
                continue
            out("  --- changed floats within 0x300..0x500 of health %#012x ---" % a)
            for i in range(0, min(len(before), len(after)) - 8, 4):
                x0, y0 = struct.unpack_from("<ff", before, i)
                x1, y1 = struct.unpack_from("<ff", after, i)
                if x0 == x1 and y0 == y1:
                    continue
                if x1 != x1 or y1 != y1:
                    continue
                if abs(x1) > 20000.0 or abs(y1) > 20000.0:
                    continue
                out("    %#012x  %10.2f -> %10.2f  |  %10.2f -> %10.2f"
                    % (a - 0x300 + i, x0, x1, y0, y1))
        out("RESULT: health-field=%#x" % moved[0][0])
        out("VERDICT: PASS - stim identified the local player's health field")
        return 0
    finally:
        try:
            g.close()
        except Exception:                        # noqa: BLE001
            pass


if __name__ == "__main__":
    sys.exit(main())

