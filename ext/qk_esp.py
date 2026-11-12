r"""qk_esp.py -- the producer: reads the game, projects, writes the overlay ring.

All values are measured from live memory (no wiki offsets):
    entity       a name hit whose (hit-0xEEC) is a plausible world position
    position     hit-0xEEC                  (verified by movement, 3x)
    view angles  hit+0x3A4 yaw / +0x3A8 pitch, degrees (found by the look-diff)
    screen       1920x1080 borderless

Writes the ring qk_overlay.exe already draws:
    Header { u32 magic 0x514B4258; u32 count; u64 frame }
    Box    { float x0,y0,x1,y1; u32 color; u32 pad }   max 256

Usage: qk_esp.py --local=kern30120 [--secs=120] [--fov=90]
                  [--trigger=1 [--trig-hitbox=BODY] [--trig-delay=60] [--trig-hold=0]
                   [--trig-key=LMB]]
"""
import ctypes
import math
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gio            # noqa: E402
import dumplive as dl  # noqa: E402
import qk_phys as PM    # noqa: E402

OFF_FILE = os.path.join(os.path.dirname(HERE), "temp", "qk_offsets.txt")


def load_offsets():
    """image_pa + vp_rva, written by qk_image --data --watch (the run that works).

    Also picks up optional `pos_delta` / `ang_off` so a build that moved the fields can be
    re-anchored without editing this file (p121 measured pos at name+0xF58, angles at
    name+0xB00 on the 07/11 build; the old name-0xEEC is dead there).
    """
    global POS_DELTA, YAW_OFF, PITCH_OFF
    try:
        with open(OFF_FILE, "r") as f:
            k = {}
            for ln in f:
                if "=" in ln:
                    a, b = ln.strip().split("=", 1)
                    k[a] = int(b, 16)
        if "pos_delta" in k:
            POS_DELTA = k.pop("pos_delta")          # signed: pos at name+POS_DELTA
        if "ang_off" in k:
            YAW_OFF = k.pop("ang_off")
            PITCH_OFF = YAW_OFF + 4
        if k.get("image_pa") and k.get("vp_rva"):
            return k
    except (OSError, ValueError):
        pass
    return None

MAGIC = 0x514B4258
POS_OFF = 0xEEC          # legacy magnitude, kept for the banner
POS_DELTA = -0xEEC       # signed: position is read at name+POS_DELTA
YAW_OFF = 0x3A4
PITCH_OFF = 0x3A8
W, H = 1920, 1080

# --fake: three synthetic entities placed so the crosshair lands in a known band of
# one of them.  (sx, sy, depth): sy is the FEET row, so the box is (sy-hgt .. sy) with
# hgt = 2400/depth.  Entity 0 is off to the right and must be skipped; entity 1 puts
# the crosshair (960,540) in its HEAD band; entity 2 is behind it.
FAKE_ENTS = [(1105.0, 650.0, 20.0), (960.0, 650.0, 20.0), (960.0, 600.0, 30.0)]


def fake_vp(fov):
    """Synthetic view-projection for PM.project's COLUMN branch: cw = z, cx = (2f/W)x,
    cy = (2f/H)y, so project() lands the round-trip below exactly on the target pixel."""
    f = 0.5 * H / math.tan(math.radians(fov) / 2.0)
    return [2.0 * f / W, 0, 0, 0,
            0, 2.0 * f / H, 0, 0,
            0, 0, 0, 1,                # m[11]=1: project()'s cw = m[11]*z -> cw = z
            0, 0, 0, 0]


def fake_world(sx, sy, depth, fov):
    """World point that projects to exactly (sx, sy) at 'depth' under fake_vp.
    Round-trip:  sx = ((2f/W)x/z*0.5+0.5)*W  ->  x = (sx-W/2)*z/f."""
    f = 0.5 * H / math.tan(math.radians(fov) / 2.0)
    return (sx - W / 2.0) * depth / f, (H / 2.0 - sy) * depth / f, depth


def out(s):
    """Log line to the console AND to --out when given: an elevated relaunch gets its
    own console, so the file is the only feed the caller can read (R3).  The console
    codepage is cp1252, hence the ascii scrub."""
    line = "".join(c if ord(c) < 128 else "?" for c in s)
    print(line, flush=True)
    if OUT_FILE:
        try:
            with open(OUT_FILE, "a") as f:
                f.write(line + "\n")
        except OSError:
            try:                                # e.g. the dir was taken away mid-run
                os.makedirs(os.path.dirname(OUT_FILE), exist_ok=True)
                with open(OUT_FILE, "a") as f:
                    f.write(line + "\n")
            except OSError:
                pass


OUT_FILE = None


def arg(name, default=None, cast=str):
    for i, a in enumerate(sys.argv):
        if a == "--" + name and i + 1 < len(sys.argv):
            return cast(sys.argv[i + 1])
        if a.startswith("--" + name + "="):
            return cast(a.split("=", 1)[1])
    return default


def find_entities(g, ranges, needle):
    """Name hits whose origin is a plausible world position -> [(hit, x, y, z)]."""
    pats = [needle.encode("utf-16-le"), needle.encode("ascii")]
    hits = []
    for rlo, rhi in ranges:
        pa = (rlo + 7) & ~7
        while pa + 0x10000 <= rhi:
            try:
                blk = dl.retry_phys(g, pa, 0x10000, tries=1)
            except OSError:
                pa += 0x10000
                continue
            for pat in pats:
                i = blk.find(pat)
                while i >= 0:
                    hits.append(pa + i)
                    i = blk.find(pat, i + 1)
            pa += 0x10000
    ents = []
    for a in hits:
        try:
            x, y, z = struct.unpack("<fff", dl.retry_phys(g, a + POS_DELTA, 12, tries=1))
        except OSError:
            continue
        if not all(abs(c) < 20000.0 for c in (x, y, z)):
            continue
        # no magnitude/height filter: the player's hit must survive to be picked as the
        # camera by its ANGLE fields, which are the stronger identifier (measured: the
        # strict position filter left 0 entities that also had real angles)
        ents.append((a, x, y, z))
    return ents


def project(ox, oy, oz, yaw, pitch, px, py, pz, fov):
    """World -> pixel from the measured angles (degrees, z-up)."""
    dy = math.radians(yaw)
    dp = math.radians(pitch)
    fx, fy, fz = math.cos(dp) * math.cos(dy), math.cos(dp) * math.sin(dy), math.sin(dp)
    rx, ry, rz = -math.sin(dy), math.cos(dy), 0.0
    ux = fy * rz - fz * ry
    uy = fz * rx - fx * rz
    uz = fx * ry - fy * rx
    dx, dyy, dz = px - ox, py - oy, pz - oz
    zv = dx * fx + dyy * fy + dz * fz
    if zv <= 1.0:
        return None
    f = 0.5 * H / math.tan(math.radians(fov) / 2.0)
    sx = W / 2.0 + (dx * rx + dyy * ry + dz * rz) * f / zv
    sy = H / 2.0 - (dx * ux + dyy * uy + dz * uz) * f / zv
    return sx, sy, zv


def main():
    global OUT_FILE
    OUT_FILE = arg("out")
    if OUT_FILE:
        # absolute on BOTH sides of the elevation hop: the elevated child inherits
        # lpDirectory=ext\, so a relative --out would resolve into ext\temp\ and every
        # log line would be silently dropped (OSError swallowed) -- a black run.
        OUT_FILE = os.path.abspath(OUT_FILE)
    secs = arg("secs", 120, lambda s: int(s, 0))
    fov = arg("fov", 90, lambda s: float(s))
    needle = arg("local", "kern30120")
    mates = [n.strip() for n in arg("mates", "").split(",") if n.strip()]
    ring_name = arg("ring", r"Local\qk_boxes")
    if not dl.elevation() and ("--no-elevate" not in sys.argv):
        # run_elevated sets lpDirectory to ext\, so both the script path and any
        # relative --out have to be absolute before the hop (a relative arg[0] made
        # the child exit 2 with "can't open file", silently, in its own console).
        argv = list(sys.argv)
        argv[0] = os.path.abspath(argv[0])
        argv = [os.path.abspath(a.split("=", 1)[1]) if a.startswith("--out=") else a
                for a in argv]
        cmd = " ".join('"%s"' % a if " " in a else a for a in argv) + " --no-elevate"
        out(dl.run_elevated(cmd))
        return 0

    out("===== qk_esp producer: pos @ name%+#x, angles @ name+%#x/%#x, %dx%d fov=%.0f ====="
        % (POS_DELTA, YAW_OFF, PITCH_OFF, W, H, fov))
    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        out("gio: %s" % e)
        return 2

    k32 = ctypes.windll.kernel32
    size = 16 + 256 * 24
    k32.CreateFileMappingW.restype = ctypes.c_void_p
    k32.MapViewOfFile.restype = ctypes.c_void_p      # without this the 64-bit view address
    k32.MapViewOfFile.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong,   # is
                                  ctypes.c_ulong, ctypes.c_size_t]                   # truncated
    hmap = k32.CreateFileMappingW(ctypes.c_void_p(-1), None, 0x04, 0, size,
                                  ctypes.c_wchar_p(ring_name))
    if not hmap:
        out("CreateFileMapping failed")
        return 2
    addr = k32.MapViewOfFile(ctypes.c_void_p(hmap), 0x0002, 0, 0, size)
    if not addr:
        out("MapViewOfFile failed")
        return 2
    buf = (ctypes.c_ubyte * size).from_address(addr)
    out("ring %s mapped (%d bytes)" % (ring_name, size))

    fake = arg("fake", 0, lambda s: int(s, 0))
    frame = 0
    trig = None
    if arg("trigger", 0, lambda s: int(s, 0)):
        try:
            import qk_trigger as TR
        except ImportError:
            out("qk_trigger.py missing - trigger stays off")
        else:
            trig = TR.Trigger(
                enabled=True, hitbox=arg("trig-hitbox", "BODY"),
                delay_ms=arg("trig-delay", 60, lambda s: float(s)),
                hold=bool(arg("trig-hold", 0, lambda s: int(s, 0))),
                button=arg("trig-key", "LMB"),
                focus_guard=bool(arg("trig-guard", 1, lambda s: int(s, 0))),
                settings=os.path.join(os.path.dirname(HERE), "temp", "qk_trigger.txt"))
            out("trigger armed: hitbox=%s delay=%.0fms hold=%d key=%s settings=%s"
                % (trig.hitbox, trig.delay_ms, trig.hold, trig.button,
                   trig.settings_file))
    try:
        ranges, _ = dl.usable_ranges(g.ram_top, None, None)
        t0 = time.time()
        if fake:
            ents = [(needle,) + fake_world(sx, sy, d, fov) for sx, sy, d in FAKE_ENTS]
            caments, tgt = ents, []
            out("fake mode: %d synthetic entities, synthetic VP (no game needed)"
                % len(ents))
        else:
            ents = find_entities(g, ranges, needle)
        caments = ents                                   # 4-tuples: (hit, x, y, z)
        out("local name hits with a readable 3-float field: %d (%.1fs)"
            % (len(ents), time.time() - t0))
        tgt = []
        for m in mates:
            tgt += [(m,) + e for e in find_entities(g, ranges, m)]
        out("mate entities (raw): %d" % len(tgt))
        # dedupe by position: a name has thousands of copies, a body has one place
        uniq = {}
        for m, a, x, y, z in tgt:
            uniq[(m, round(x), round(y), round(z))] = (a, x, y, z)
        tgt = [(m, a, x, y, z) for (m, a, x, y, z) in
               [(k[0],) + v for k, v in uniq.items()]]
        out("mate entities (deduped by position): %d" % len(tgt))
        if not ents:
            return 8
        ents = tgt if tgt else [(needle,) + e for e in caments]
        while time.time() - t0 < secs:
            if frame < 6:
                out("dbg it=%d begin" % frame)
            if frame % 60 == 0 and frame and not fake:
                ents = [(needle,) + e for e in find_entities(g, ranges, needle)]
            # static-offset read: image_pa + vp_rva is the live view-projection
            off = load_offsets()
            if fake:
                mat = fake_vp(fov)
            elif not off:
                out("no temp\\qk_offsets.txt - run qk_image --data --watch first")
                return 8
            else:
                try:
                    mat = struct.unpack("<16f", dl.retry_phys(g, off["image_pa"] + off["vp_rva"],
                                                              64, tries=3))
                except OSError as e:
                    out("matrix read fault: %s" % e)
                    return 5
            if frame == 0:
                if fake:
                    out("vp fake (fov=%.0f) : m15=%.4f m11=%.4f" % (fov, mat[15], mat[11]))
                else:
                    out("vp from image_pa=%#x rva=%#x : m15=%.4f m11=%.4f"
                        % (off["image_pa"], off["vp_rva"], mat[15], mat[11]))
            if frame < 6:
                out("dbg it=%d mat ok" % frame)
            geoms = []
            for (_m, _ea, ex, ey, ez) in ents:
                p = PM.project(mat, ex, ey, ez, W, H)
                if not p:
                    continue
                sx, sy, zv = p[0], p[1], p[2]      # project returns (sx, sy, depth, tag)
                if not (0 <= sx <= W and 0 <= sy <= H):
                    continue
                hgt = max(24.0, min(420.0, 2400.0 / zv))
                wid = hgt * 0.45
                geoms.append((sx - wid / 2, sy - hgt, sx + wid / 2, sy))

            # the trigger reads the same boxes the overlay draws; the box it has
            # under the crosshair is drawn in a different colour, so the trigger's
            # state is visible as a pixel (R8) and not only as a log line.
            trig_state = ""
            if trig is not None:
                if frame % 15 == 0:
                    trig.reload()
                trig.feed(geoms, W / 2.0, H / 2.0)
                trig_state = trig.last_state
            if frame < 6:
                out("dbg it=%d feed ok geoms=%d state=%s" % (frame, len(geoms), trig_state))
            tb = trig.target if trig is not None else None

            boxes = []
            for bx in geoms:                   # NOT 'g': that name is the gio handle, and the
                col = 0xFF00FFFF if (tb is not None and bx is tb) else 0xFF40FF40   # old loop killed it
                boxes.append((bx[0], bx[1], bx[2], bx[3], col))
            struct.pack_into("<IIQ", buf, 0, MAGIC, len(boxes), frame)
            for i, (x0, y0, x1, y1, col) in enumerate(boxes[:256]):
                struct.pack_into("<ffffII", buf, 16 + i * 24, x0, y0, x1, y1, col, 0)
            frame += 1
            if frame % 10 == 0:
                out("frame %d boxes=%d m15=%.3f m11=%.3f %s"
                    % (frame, len(boxes), mat[15], mat[11], trig_state))
            time.sleep(0.02)
    finally:
        try:
            g.close()
        except Exception:                        # noqa: BLE001
            pass
    out("producer done, frames=%d" % frame)
    return 0


if __name__ == "__main__":
    sys.exit(main())

