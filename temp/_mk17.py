r"""_mk17.py -- waiting transport for the first in-game read-back (Q1).

Why: qk_va/qk_session already resolve dtb+base and hunt the entity array, but they
return 3 instantly when the game is not up, so a human must hit "run" at the right
second.  This waits for the pid, does the pass ONCE, and writes one file - the file
is the state feed (R3), the console is not.

Modes
  --preflight      device open + 3 R10-guarded reads, then exit (replaces _d0_probe)
  --wait-pid=N     poll find_pid() every 2 s for N s, then run
  --pid=N          run immediately against a known pid
Out: temp\_mk17_out.txt (own file, R5).  RESULT:/VERDICT: name the variable.
Read-only: device open + physical reads.  No load/DSE/service/bcdedit (R1).
"""
import math
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))

import dumplive as dl   # noqa: E402
import gio              # noqa: E402
import qk_va as Q       # noqa: E402
import qk_vp as qv      # noqa: E402

sys.path.insert(0, HERE)
import _vp2d as vp      # noqa: E402  (rect math, self-checked)

NO_ELEV = "--no-elevate" in sys.argv


def _arg(name, default=None):
    p = "--" + name + "="
    for a in sys.argv:
        if a.startswith(p):
            return a[len(p):]
    return default


OUT = _arg("out", os.path.join(HERE, "_mk17_out.txt"))


def say(s=""):
    line = "" if s == "" else ("%s %s" % (time.strftime("%H:%M:%S"), s))
    print(line)
    with open(OUT, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def score_vp(buf):
    """Plausibility of a 4x4 as a world->view matrix, for either layout.

    A view matrix has a translation in column 3 and either
      classic      row 3 = 0001, forward on row 2   (row-vector, Source/EA)
      perspective  row 3 = forward, w = depth       (what vp_from_yaw_pitch builds)
    Scoring only the classic form would silently throw away a perspective build.
    """
    try:
        v = struct.unpack("<16f", buf)
    except struct.error:
        return -1, None
    if any(x != x or abs(x) > 1e6 for x in v):      # NaN / absurd
        return -1, v
    s = 0
    f3 = math.sqrt(v[12] ** 2 + v[13] ** 2 + v[14] ** 2)
    classic = f3 < 1e-6
    if classic:
        s += 2                                      # row 3 empty
        if abs(v[15] - 1.0) < 1e-3:
            s += 2                                  # row 3 == 0001
    elif 0.5 < f3 < 2.0:
        s += 2                                      # unit forward row; m[15] is -fwd.cam,
                                                    # so its size says nothing
    fwd = (v[8], v[9], v[10]) if classic else (v[12], v[13], v[14])
    n = math.sqrt(fwd[0] ** 2 + fwd[1] ** 2 + fwd[2] ** 2)
    if 1e-4 < abs(v[0]) < 20.0:
        s += 1
    if 1e-4 < abs(v[5]) < 20.0:
        s += 1
    if 0.9 < n < 1.1:
        s += 1                                      # forward row is normalised
    if any(v[i] != 0.0 for i in range(12)):
        s += 1
    return s, v


def _f32(buf, at):
    try:
        return struct.unpack_from("<3f", buf, at)
    except struct.error:
        return None


def _vec_ok(v, lim=1.0e6):
    return bool(v) and all(x == x and abs(x) < lim for x in v)


FALLBACK_MINS = (-16.0, -16.0, 0.0)
FALLBACK_MAXS = (16.0, 16.0, 72.0)


def entity_pass(rd, array_va, mat, w, h, tag, slots=48, wsrc="w"):
    """Follow an entity array and turn each object into a screen rect.

    Per object: vtable (identity), m_localOrigin 0x18 (world pos), m_iTeamNum 0x340,
    then m_Collision 0x3c8 -> m_vecMins 0x10 / m_vecMaxs 0x18 for the real extents
    (falls back to a player-sized box when that pointer is not readable).

    Offsets are the dm32 ones verified in docs\\ref\\NETVAR_LOCAL.md: m_localOrigin is
    at 0x18 on DT_BaseEntity and on every other entity class alike, so one chain
    works for players and props.  m_vecAbsOrigin on DT_Player is the dumper's 0x0
    gap and is NOT used.
    """
    rows, seen, vt_hits, bounds_ok = [], set(), 0, 0
    for blk in range(0, slots, 8):
        buf = rd.read(array_va + blk * 8, 64)
        if not buf:
            continue
        for i in range(0, len(buf) - 7, 8):
            idx = blk + i // 8
            q = struct.unpack_from("<Q", buf, i)[0]
            if not (0x10000 <= q < 0x7FFFFFFFFFFF) or q & 7 or q in seen:
                continue
            seen.add(q)
            vt = rd.read(q, 8)
            if vt:
                v = struct.unpack("<Q", vt)[0]
                if 0x10000 <= v < 0x7FFFFFFFFFFF:
                    vt_hits += 1
            ob = rd.read(q + 0x18, 0x2C)          # origin 0x18 .. team 0x340 is far, split
            if not ob:
                continue
            org = _f32(ob, 0)
            if not _vec_ok(org):
                continue
            tb = rd.read(q + 0x340, 4)
            team = struct.unpack("<i", tb)[0] if tb and len(tb) == 4 else -1
            mins, maxs, src = FALLBACK_MINS, FALLBACK_MAXS, "fallback"
            cp = rd.read(q + 0x3c8, 8)
            if cp:
                c = struct.unpack("<Q", cp)[0]
                if 0x10000 <= c < 0x7FFFFFFFFFFF and c & 3 == 0:
                    cb = rd.read(c + 0x10, 0x18)
                    mn, mx = _f32(cb, 0), _f32(cb, 0x0C) if cb else (None, None)
                    if _vec_ok(mn, 400.0) and _vec_ok(mx, 400.0) \
                            and all(mn[k] < mx[k] for k in range(3)) \
                            and all(mx[k] - mn[k] < 400.0 for k in range(3)):
                        mins, maxs, src = mn, mx, "coll"
                        bounds_ok += 1
            r = vp.rect_for(mat, org, mins, maxs, w, h, tag, wsrc=wsrc)
            rows.append({"idx": idx, "obj": q, "team": team, "org": org,
                         "bounds": src, "rect": r})
    return rows, {"slots": len(seen), "vt": vt_hits, "coll": bounds_ok}


def report(rows, label):
    on = [r for r in rows if r["rect"]]
    say("PASS %s: objs=%d onscreen=%d coll_bounds=%d"
        % (label, len(rows), len(on), sum(1 for r in rows if r["bounds"] == "coll")))
    for r in rows[:48]:
        rr = r["rect"]
        box = ("%.0f,%.0f-%.0f,%.0f" % (rr["x0"], rr["y0"], rr["x1"], rr["y1"])
               if rr else "-")
        say("ENT i=%d obj=%#x team=%d %s %s org=%.1f,%.1f,%.1f rect=%s"
            % (r["idx"], r["obj"], r["team"], r["bounds"], "D" if rr else "-",
               r["org"][0], r["org"][1], r["org"][2], box))
    return len(on)


def preflight():
    say("===== _mk17 preflight (device liveness only) =====")
    try:
        g = gio.Gio()
    except OSError as e:
        say("RESULT: gio open FAILED err=%r" % e)
        say("VERDICT: FAIL - no transport (R1: VM first, never 'just try the host')")
        return 1
    try:
        say("PRE ram_top=%#x installed=%d MiB" % (g.ram_top, g.ram_top // 0x100000))
        ranges, note = dl.usable_ranges(g.ram_top)
        say("RAMMAP %s ranges=%d" % (note, len(ranges)))
        if not ranges:
            say("RESULT: no usable ranges")
            say("VERDICT: FAIL - empty RAM map")
            return 2
        a, b = ranges[0]
        _lo, hi = ranges[-1]
        targets = [a + 0x1000, (a + b) // 2 & ~0xFFFFF, hi - 0x1000]
        bad = 0
        for pa in targets:
            try:
                blk = g.read_phys(pa, 8)
                say("READ pa=%#012x -> %s" % (pa, blk.hex(" ")))
            except OSError as e:
                bad += 1
                say("READ pa=%#012x -> ERR %r" % (pa, e))
        say("RESULT: ram_top_ok=1 ranges=%d reads=3 fails=%d" % (len(ranges), bad))
        say("VERDICT: %s - transport %s"
            % ("PASS" if bad < 3 else "PARTIAL", "alive" if bad < 3 else "degraded"))
        return 0 if bad < 3 else 3
    finally:
        g.close()


def wait_pid(secs):
    say("WAIT for game pid up to %d s (poll 2 s)" % secs)
    end = time.time() + secs
    while time.time() < end:
        pid = dl.find_pid() or 0
        if pid:
            say("FOUND pid=%d after %.0f s" % (pid, secs - (end - time.time())))
            return pid
        time.sleep(2)
    return 0


def main():
    if not NO_ELEV and not dl.elevation():
        cmd = '"%s" "%s" --no-elevate --out="%s"' % (
            sys.executable, os.path.abspath(__file__), OUT)
        for a in sys.argv[1:]:
            if a.startswith(("--preflight", "--wait-pid=", "--pid=", "--out=")):
                cmd += " " + ('"%s"' % a if " " in a else a)
        try:
            os.remove(OUT)
        except OSError:
            pass
        print("not elevated - relaunching elevated, output -> %s" % OUT)
        print(dl.run_elevated(cmd))
        return 0

    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("# _mk17 out  %s\n" % time.strftime("%Y-%m-%d %H:%M:%S"))

    if "--preflight" in sys.argv:
        return preflight()

    say("===== _mk17 (wait -> map -> PE identity -> VP -> array) =====")
    pid = int(_arg("pid", "0"), 0)
    if not pid:
        pid = wait_pid(int(_arg("wait-pid", "600"), 0))
    if not pid:
        say("RESULT: no game process")
        say("VERDICT: PARTIAL - target absent (no in-game half ran; R9)")
        return 3

    try:
        g = gio.Gio()
    except OSError as e:
        say("RESULT: gio open FAILED err=%r" % e)
        say("VERDICT: FAIL - no transport")
        return 2
    try:
        say("PRE pid=%d ram_top=%#x" % (pid, g.ram_top))
        t0 = time.time()
        try:
            m = Q.get_map(g, pid)
        except OSError as e:
            say("get_map OSError: %r" % e)
            m = None
        say("map took %.1f s" % (time.time() - t0))
        if not m:
            say("RESULT: no-dtb")
            say("VERDICT: FAIL - page tables not resolved (cache, driver, PEB all failed)")
            return 4
        say("RESULT: map dtb=%#x base=%#x" % (m["dtb"], m["base"]))
        rd = Q.Reader(g, m["dtb"])
        pe_rc = Q.act_pe(rd, m["base"])
        if pe_rc != 0:
            say("RESULT: PE identity failed rc=%d" % pe_rc)
            say("VERDICT: FAIL - MZ/PE unreadable at base")
            return 5

        best = (0, None, 0)
        for i, rva in enumerate(qv.RVAS):
            try:
                buf = rd.read(m["base"] + rva, 0x40)
            except OSError as e:
                say("VP[%d] rva=%#x ERR %r" % (i, rva, e))
                continue
            if not buf:
                say("VP[%d] rva=%#x no-bytes" % (i, rva))
                continue
            s, v = score_vp(buf)
            say("VP[%d] rva=%#x score=%d" % (i, rva, s))
            for r in range(4):
                say("   %s" % " ".join("%+.5f" % x for x in v[r * 4:r * 4 + 4]))
            if s > best[0]:
                best = (s, v, rva)
        say("RESULT: vp_best score=%d rva=%s"
            % (best[0], "%#x" % best[2] if best[2] else "-"))

        ents = Q.act_find_array(rd, m["base"])
        n = len(ents) if ents else 0
        say("RESULT: array candidates=%d" % n)
        say("reads=%d faults=%d" % (rd.reads, rd.faults))
        ok_vp = best[0] >= 4
        if not (n and ok_vp):
            say("VERDICT: PARTIAL - map ok but %s"
                % ("array empty" if ok_vp else
                   ("vp weak" if n else "vp weak and array empty")))
            return 6

        # ---- step 5: entity -> rect -------------------------------------
        # Matrix source is a declared variable, printed so the log names it.
        w, h = int(_arg("w", "1920")), int(_arg("h", "1080"))
        cam = _arg("cam")
        if cam:
            cx, cy, cz = [float(x) for x in cam.split(",")]
            mat = vp.vp_from_yaw_pitch(float(_arg("yaw", "0")),
                                       float(_arg("pitch", "0")),
                                       (cx, cy, cz), w, h)
            msrc, mtags = "cam(yaw,pitch)", ["row"]
        else:
            mat = list(best[1])
            msrc, mtags = "viewmatrix rva=%#x" % best[2], ["row", "col"]
        wsrc = vp.layout_of(mat)
        if wsrc is None:                     # no row-major depth row: try both tags
            wsrc = "w"
            say("WARN layout undecidable (no depth row carries |w|>1e-6) - assuming "
                "perspective 'w'; a classic matrix would be wrong here")
        else:
            mtags = ["row"]                  # a real ViewMatrix is row-major
        say("MATRIX %s w=%d h=%d layout=%s tags=%s"
            % (msrc, w, h, wsrc, ",".join(mtags)))
        say("CAMERA derived=%s" % ("yes" if vp.cam_from_rows(mat) else "no"))

        pick, pick_on, pick_tag, pick_v = None, -1, None, None
        for vt, nc, rva, ava in ents[:3]:
            for tag in mtags:
                try:
                    rows, st = entity_pass(rd, ava, mat, w, h, tag, wsrc=wsrc)
                except OSError as e:
                    say("PASS array=%#x tag=%s ERR %r" % (ava, tag, e))
                    continue
                on = report(rows, "array=%#x vt=%d slots=%d tag=%s"
                            % (ava, vt, st["slots"], tag))
                v = vp.verify(rows, mat, tag)
                say("  stats array=%#x tag=%s slots=%d vt=%d coll=%d onscreen=%d "
                    "aspect=%d anchor=%s local=%d"
                    % (ava, tag, st["slots"], st["vt"], st["coll"], on, v["aspect"],
                       "-" if v["anchor"] is None else "%.1f" % v["anchor"], v["local"]))
                if on > pick_on:
                    pick, pick_on, pick_tag, pick_v = (vt, nc, rva, ava), on, tag, v
        if not pick:
            say("RESULT: no candidate produced entities")
            say("VERDICT: PARTIAL - array found (%d) but no entity read" % n)
            return 7
        anchored = pick_v["anchor"] is not None and pick_v["anchor"] <= 128.0
        say("RESULT: best array=%#x tag=%s onscreen=%d aspect=%d anchor=%s local=%d "
            "reads=%d faults=%d"
            % (pick[3], pick_tag, pick_on, pick_v["aspect"],
               "-" if pick_v["anchor"] is None else "%.1f" % pick_v["anchor"],
               pick_v["local"], rd.reads, rd.faults))
        if pick_on >= 3 and anchored and pick_v["aspect"] >= pick_on * 0.6:
            say("VERDICT: PASS - %d rects, local player anchored at %.1f units to the "
                "derived camera, array %#x rva %#x tag %s"
                % (pick_on, pick_v["anchor"], pick[3], pick[2], pick_tag))
            return 0
        say("VERDICT: PARTIAL - %d rects, anchor %s, aspect %d/%d (needs >=3 rects, "
            "anchor <=128, most rects human-shaped)"
            % (pick_on, "none" if pick_v["anchor"] is None else
               "%.1f" % pick_v["anchor"], pick_v["aspect"], pick_on))
        return 7
    finally:
        try:
            g.close()
        except Exception:                       # noqa: BLE001
            pass


if __name__ == "__main__":
    sys.exit(main())
