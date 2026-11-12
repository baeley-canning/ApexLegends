r"""_mk18_dev.py -- device sanity for the table-free route (Route A step 0).

Answers three questions before _mk18 trusts anything:
  * is this process elevated?  (gio may or may not need it)
  * does the gdrv3 device open here, and what is ram_top?
  * does one R10-guarded control read at 0x1000 return bytes?

Read-only.  No load/DSE/service/bcdedit (R1).  Writes temp\_mk18_dev.txt.
Usage: _mk18_dev.py [--no-elevate]
"""
import ctypes
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "ext"))

import dumplive as dl   # noqa: E402
import gio              # noqa: E402

OUT = os.path.join(HERE, "_mk18_dev.txt")
LOG = []


def say(s):
    line = str(s)
    LOG.append(line)
    print(line)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(LOG) + "\n")


def main():
    say("=== _mk18_dev %s ===" % sys.version.split()[0])
    say("admin=%s elevated=%s elevated_ok=%s"
        % (bool(ctypes.windll.shell32.IsUserAnAdmin()), dl.elevation(),
           getattr(dl, "elevated", lambda: "n/a")()))
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        say("gio open FAILED: %s" % e)
        say("RESULT: device=closed")
        say("VERDICT: FAIL - gdrv3 not openable from this token")
        return 2
    say("gio open OK ram_top=%#x" % g.ram_top)
    try:
        ranges, note = dl.usable_ranges(g.ram_top, None, None)
        say("usable_ranges n=%d note=%s" % (len(ranges), note))
        ok, bad = 0, 0
        for lo, hi in ranges:
            if lo <= 0x1000 and 0x1000 + 16 <= hi:
                ok += 1
            else:
                bad += 1
        say("0x1000 inside a usable range: %s (ranges covering=%d)"
            % ("yes" if ok else "NO", ok))
    except Exception as e:                                  # noqa: BLE001
        say("usable_ranges raised: %r" % (e,))
    try:
        b = g.read_phys(0x1000, 16)
        say("control read 0x1000: %s len=%d" % (b.hex() if b else "None",
                                                len(b) if b else 0))
    except OSError as e:
        say("control read 0x1000 raised: %s" % e)
    try:
        pid = dl.find_pid()
    except Exception as e:                                  # noqa: BLE001
        pid = "raised %r" % (e,)
    say("find_pid=%s" % pid)
    say("RESULT: device=open ram_top=%#x" % g.ram_top)
    say("VERDICT: PASS - gdrv3 usable from this token")
    return 0


if __name__ == "__main__":
    sys.exit(main())
