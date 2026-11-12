r"""_p122.py -- PROBE p122: nail the layout the p121 hit exposed.

p121 hit 6/7/8 proved a single object carries all three names 0xF apart (16-byte name
slots) and that +0x0F58 from it reads a world position AND angles yaw=-139.23 pitch=11.15.
The old -0xEEC anchor is dead for this build; the real one is positive.

This probe reads that object once and reports, exactly:
  * where the name array is, and how far the slots really are apart
  * the offset of the position triple (-21.88, 26.12, -7705.43) by bit pattern
  * the offset of the angle pair (-139.23, 11.15) by bit pattern
  * a hex/float dump so the two offsets can be read by eye

Fixed addresses (valid for the session that produced p121): 0x143f32bf8 base name.
Read-only, gdrv3 only.  Writes temp\_p122_out.txt / _p122_dump.txt.
RESULT:/VERDICT: name the variable (R5).  Usage: _p122.py [--name=0x143f32bf8]
"""
import math
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import _p116 as P  # noqa: E402

EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio             # noqa: E402
import dumplive as dl  # noqa: E402

OUT = os.path.join(HERE, "_p122_out.txt")
DUMP = os.path.join(HERE, "_p122_dump.txt")
NAME = 0x143f32bf8
POS = (-21.88, 26.12, -7705.43)
ANG = (-139.23, 11.15)
LO = NAME - 0x100
LEN = 0x1280


def say(s):
    line = "".join(c if ord(c) < 128 else "?" for c in str(s))
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def comps(v, tol):
    out = []
    for b in (-0.0, 0.0):
        pass
    b0 = struct.pack("<f", v)
    out.append(b0)
    return out


def near(buf, want, tol, count=1):
    hits = []
    for i in range(0, len(buf) - 4 * count, 4):
        ok = True
        for k in range(count):
            f = struct.unpack("<f", buf[i + 4 * k:i + 4 * k + 4])[0]
            if math.isnan(f) or abs(f - want[k]) > tol:
                ok = False
                break
        if ok:
            hits.append(i)
    return hits


def main():
    global NAME
    for a in sys.argv:
        if a.startswith("--name="):
            NAME = int(a.split("=", 1)[1], 0)
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s" --name=%#x' % (os.path.abspath(__file__), NAME)))
        return 0
    open(OUT, "w").close()
    say("=== p122 layout %s name=%#x win=%#x+%#x ===" % (time.strftime("%H:%M:%S"), NAME, LO, LEN))
    pid = dl.find_pid()
    say("game_pid=%s" % pid)
    if pid is None:
        say("RESULT: game_pid=none")
        say("VERDICT: PARTIAL - game not running (R9)")
        return 3
    try:
        g = gio.Gio(chunk=P.CHUNK)
    except OSError as e:
        say("gio: %s" % e)
        return 2
    ranges, note = dl.usable_ranges(g.ram_top, LO, LO + LEN)
    say("ranges=%d note=%s" % (len(ranges), note))
    try:
        buf = dl.retry_phys(g, LO, LEN, tries=3)
    except Exception as e:                                    # noqa: BLE001
        say("read fault %s: %s" % (type(e).__name__, e))
        g.close()
        say("RESULT: read=fault")
        say("VERDICT: FAIL - window unreadable")
        return 4
    g.close()
    if len(buf) < LEN:
        say("short read %#x of %#x" % (len(buf), LEN))
    with open(DUMP, "w", encoding="utf-8") as f:
        for i in range(0, len(buf), 16):
            hx = " ".join("%02x" % b for b in buf[i:i + 16])
            fc = " ".join("%9.3f" % struct.unpack("<f", buf[i + k:i + k + 4])[0]
                          for k in range(0, 16, 4) if i + k + 4 <= len(buf))
            asc = "".join(chr(b) if 0x20 <= b < 0x7F else "." for b in buf[i:i + 16])
            f.write("%+#08x %-47s %-40s %s\n" % (LO + i, hx, fc, asc))
    ph = near(buf, POS, 0.02, 3)
    ah = near(buf, ANG, 0.02, 2)
    for i in ph:
        say("pos %#x  a=%#x  delta_from_name=%+#x  %s"
            % (LO + i, LO + i, (LO + i) - NAME, POS))
    for i in ah:
        say("ang %#x  a=%#x  delta_from_name=%+#x  %s"
            % (LO + i, LO + i, (LO + i) - NAME, ANG))
    say("name_slots:")
    for k in range(4):
        a = NAME + k * 16
        i = a - LO
        raw = buf[i:i + 16]
        say("  %#x %s |%s|" % (a, raw.hex(), "".join(chr(b) if 0x20 <= b < 0x7F else "." for b in raw)))
    if ph and ah:
        d = (LO + ah[0]) - (LO + ph[0])
        say("RESULT: pos_delta=%+#x ang_delta=%+#x ang_minus_pos=%+#x"
            % (ph[0] - (NAME - LO), ah[0] - (NAME - LO), d))
        say("VERDICT: PASS - position and angle offsets measured off the name array")
        return 0
    say("RESULT: pos_hits=%d ang_hits=%d" % (len(ph), len(ah)))
    say("VERDICT: PARTIAL - %s" % ("position only" if ph else
                                   "angles only" if ah else "neither (stale object?)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())

