"""t11_transport_gate.py - prove the T1 transport opens and reads, no game needed.

Gate (PLAN 19/11 rule 2): `gio.Gio()` must open AND a physical read inside the
RAM map must return bytes.  `sc query STATE 4` alone is not a verdict.

Elevates itself.  Writes _ritual/_t11_gate.txt; RESULT/VERDICT name the variable.
"""
import os
import sys

HERE = r"C:\Users\New User\OneDrive\Desktop\cheating"
sys.path.insert(0, os.path.join(HERE, "ext"))

import gio          # noqa: E402
import dumplive as dl  # noqa: E402

OUT = r"C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_t11_gate.txt"
L = []


def out(s):
    L.append(s)


def main():
    out("t11 transport gate  elevated=%s" % dl.elevation())
    try:
        g = gio.Gio()
    except OSError as e:
        out("RESULT: gio open failed: %s" % e)
        out("VERDICT: FAIL - T1 transport does not open")
        return 2
    try:
        out("gio open OK (\\\\.\\GIOV3)")
        out("ram_top=0x%X" % g.ram_top)
        ranges, note = dl.usable_ranges(g.ram_top)
        out("rammap %s ranges=%d" % (note, len(ranges)))
        if not ranges:
            out("VERDICT: FAIL - empty RAM interval set (R10: no safe PA)")
            return 4
        pa = ranges[0][0] + 0x1000
        b = g.read_phys(pa, 16)
        out("read_phys(%#x,16) -> %r" % (pa, b))
        if not b:
            out("VERDICT: FAIL - read returned no bytes")
            return 5
        out("RESULT: gdrv3 opened and returned %d bytes at a RAM-mapped PA" % len(b))
        out("VERDICT: PASS - T1 transport (no driver of ours loaded)")
        return 0
    finally:
        try:
            g.close()
        except Exception:                   # noqa: BLE001
            pass
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("\n".join(L) + "\n")


if __name__ == "__main__":
    if not dl.elevation() and "--no-elevate" not in sys.argv:
        argv = [os.path.abspath(sys.argv[0]), "--no-elevate"]
        print(dl.run_elevated(" ".join('"%s"' % a if " " in a else a for a in argv)))
        sys.exit(0)
    sys.exit(main())
