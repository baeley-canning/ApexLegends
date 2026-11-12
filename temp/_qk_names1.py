r"""_qk_names1.py -- PROBE p115: find every entity object WITHOUT being told a name.

Needle-free sweep.  Entity objects embed the player name as UTF-16 (qk_world
`read_utf16_name` at obj+name_off); the existing find_entities only hits names it is
handed on the CLI because the needle is the name itself.  This scans physical RAM for
*any* UTF-16/ASCII printable run and keeps only runs that sit in a real entity object:

    position  a-0xEEC   finite, |c| < 20000          (the find_entities filter)
    angles    a+0x3A4   finite, |yaw| <= 360, |pitch| <= 90   (stronger identifier)

Every survivor is logged WITH its decoded name -- that is the whole deliverable.
Read-only, gdrv3 only, no kdu, no dtb, no apexdrv.  R10: ranges from usable_ranges.

Writes temp\_qk_names1.txt (log) and temp\qk_names1.json (table).
RESULT:/VERDICT: name the variable (R5).  Usage: _qk_names1.py [--secs=180] [--max=4000]
"""
import json
import math
import os
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import gio             # noqa: E402
import dumplive as dl  # noqa: E402

OUT = os.path.join(HERE, "_qk_names1.txt")
JS = os.path.join(HERE, "qk_names1.json")
POS_OFF = 0xEEC
YAW_OFF = 0x3A4
W16 = re.compile(rb"(?:[\x20-\x7e]\x00){3,}")
A8 = re.compile(rb"[\x20-\x7e]{5,}")


def say(s):
    line = "".join(c if ord(c) < 128 else "?" for c in str(s))
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def arg(name, default, cast=int):
    for i, a in enumerate(sys.argv):
        if a.startswith("--" + name + "="):
            return cast(a.split("=", 1)[1])
        if a == "--" + name and i + 1 < len(sys.argv):
            return cast(sys.argv[i + 1])
    return default


def f3(blob):
    try:
        v = struct.unpack("<fff", blob)
    except struct.error:
        return None
    for c in v:
        if math.isnan(c) or math.isinf(c) or abs(c) > 20000.0:
            return None
    return v


def ang(blob):
    try:
        y, p = struct.unpack("<ff", blob)
    except struct.error:
        return None
    if math.isnan(y) or math.isnan(p) or math.isinf(y) or math.isinf(p):
        return None
    if abs(y) > 360.0 or abs(p) > 90.0:
        return None
    return y, p


def name_at(g, a, blk, blo):
    """Decoded name at absolute a, taken from the in-memory block when it fits."""
    i = a - blo
    if 0 <= i and i + 64 <= len(blk):
        raw = blk[i:i + 64]
        out = bytearray()
        for j in range(0, 64, 2):
            if raw[j + 1] != 0:
                break
            c = raw[j]
            if c < 0x20 or c > 0x7E:
                break
            out.append(c)
        return out.decode("ascii")
    try:
        raw = dl.retry_phys(g, a, 64, tries=1)
    except OSError:
        return ""
    s = raw.decode("utf-16-le", "replace").split("\x00")[0]
    return s if all(0x20 <= ord(c) <= 0x7E for c in s) else ""


def main():
    secs = arg("secs", 180)
    maxc = arg("max", 4000)
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    try:
        os.remove(JS)
    except OSError:
        pass
    say("=== p115 names1 %s : no needle, pos@a-%#x + angles@a+%#x ==="
        % (time.strftime("%H:%M:%S"), POS_OFF, YAW_OFF))
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        say("gio: %s" % e)
        return 2
    ranges, _ = dl.usable_ranges(g.ram_top, None, None)
    say("ranges=%d ram_top=%#x" % (len(ranges), g.ram_top))
    blocks = fails = nmatch = 0
    pos_ok = []
    t0 = time.time()
    try:
        for rlo, rhi in ranges:
            # start so that the *lowest* read (a - POS_OFF) is still inside the range:
            # a read below rlo lands in the MMIO hole and that is what bugchecks (R10)
            pa = (rlo + POS_OFF + 0xF) & ~0xF
            while pa + 0x10000 <= rhi:
                if time.time() - t0 > secs or len(pos_ok) >= maxc:
                    break
                try:
                    blk = dl.retry_phys(g, pa, 0x10000, tries=1)
                except OSError:
                    fails += 1
                    pa += 0x10000
                    continue
                blocks += 1
                seen = set()
                for rx in (W16, A8):
                    for m in rx.finditer(blk):
                        a = pa + m.start()
                        if a in seen:
                            continue
                        seen.add(a)
                        nmatch += 1
                        try:
                            pb = dl.retry_phys(g, a - POS_OFF, 12, tries=1)
                        except OSError:
                            continue
                        if f3(pb) is None:
                            continue
                        pos_ok.append(a)
                pa += 0x10000
                if blocks % 4000 == 0:
                    say("  prog blocks=%d fails=%d match=%d pos=%d (%.0fs)"
                        % (blocks, fails, nmatch, len(pos_ok), time.time() - t0))
            if time.time() - t0 > secs or len(pos_ok) >= maxc:
                break
        say("sweep blocks=%d fails=%d match=%d pos_pass=%d (%.1fs)"
            % (blocks, fails, nmatch, len(pos_ok), time.time() - t0))
        ents = []
        for a in pos_ok:
            try:
                ab = dl.retry_phys(g, a + YAW_OFF, 8, tries=1)
                pb = dl.retry_phys(g, a - POS_OFF, 12, tries=1)
            except OSError:
                continue
            an = ang(ab)
            pv = f3(pb)
            nm = name_at(g, a, b"", a)
            if len(nm) < 2 or not nm.strip():
                continue
            ents.append({"a": a, "name": nm, "pos": list(pv),
                         "yaw": an[0] if an else None, "pitch": an[1] if an else None})
        with_ang = [e for e in ents if e["yaw"] is not None]
        say("names=%d with_sane_angles=%d" % (len(ents), len(with_ang)))
        keep = with_ang if with_ang else ents
        if not keep:
            say("RESULT: candidates=0")
            say("VERDICT: FAIL - no entity-shaped name field found")
            return 4
        uniq = {}
        for e in keep:
            uniq[(e["name"], round(e["pos"][0]), round(e["pos"][1]), round(e["pos"][2]))] = e
        rows = list(uniq.values())
        say("unique(name,pos)=%d" % len(rows))
        for e in rows[:60]:
            say("  %-24s %9.1f %9.1f %9.1f  yaw=%s pitch=%s  a=%#x"
                % (e["name"][:24], e["pos"][0], e["pos"][1], e["pos"][2],
                   ("%.1f" % e["yaw"]) if e["yaw"] is not None else "-",
                   ("%.1f" % e["pitch"]) if e["pitch"] is not None else "-", e["a"]))
        with open(JS, "w") as f:
            json.dump(rows, f, indent=1)
        names = sorted({e["name"] for e in rows})
        say("distinct names=%d %s" % (len(names), names[:25]))
        say("RESULT: candidates=%d unique=%d angles_sane=%d" % (len(ents), len(rows), len(with_ang)))
        say("VERDICT: PASS - %d names discovered without input" % len(names))
        return 0
    finally:
        try:
            g.close()
        except Exception:                 # noqa: BLE001
            pass


if __name__ == "__main__":
    sys.exit(main())

