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

MAGIC = 0x514B4258
POS_OFF = 0xEEC
YAW_OFF = 0x3A4
PITCH_OFF = 0x3A8
W, H = 1920, 1080


def out(s):
    print(s, flush=True)


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
            x, y, z = struct.unpack("<fff", dl.retry_phys(g, a - POS_OFF, 12, tries=1))
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
    secs = arg("secs", 120, lambda s: int(s, 0))
    fov = arg("fov", 90, lambda s: float(s))
    needle = arg("local", "kern30120")
    mates = [n.strip() for n in arg("mates", "").split(",") if n.strip()]
    ring_name = arg("ring", r"Local\qk_boxes")
    if not dl.elevation() and ("--no-elevate" not in sys.argv):
        cmd = " ".join('"%s"' % a if " " in a else a for a in sys.argv) + " --no-elevate"
        out(dl.run_elevated(cmd))
        return 0

    out("===== qk_esp producer: pos @ name-%#x, angles @ name+%#x/%#x, %dx%d fov=%.0f ====="
        % (POS_OFF, YAW_OFF, PITCH_OFF, W, H, fov))
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

    frame = 0
    try:
        ranges, _ = dl.usable_ranges(g.ram_top, None, None)
        t0 = time.time()
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
            if frame % 60 == 0 and frame:
                ents = [(needle,) + e for e in find_entities(g, ranges, needle)]
            cam = None
            for c in caments[:64]:
                try:
                    y2, p2 = struct.unpack("<ff", dl.retry_phys(g, c[0] + YAW_OFF, 8, tries=1))
                except OSError:
                    continue
                if -360.0 < y2 < 360.0 and -90.0 < p2 < 90.0 and (abs(y2) > 0.5 or abs(p2) > 0.5):
                    cam, yaw, pitch = c, y2, p2
                    break
            if cam is None:
                time.sleep(0.02)
                continue
            boxes = []
            for (_m, _ea, ex, ey, ez) in ents:
                p = project(cam[1], cam[2], cam[3], yaw, pitch, ex, ey, ez, fov)
                if not p:
                    continue
                sx, sy, zv = p
                if not (0 <= sx <= W and 0 <= sy <= H):
                    continue
                hgt = max(24.0, min(420.0, 2400.0 / zv))
                wid = hgt * 0.45
                boxes.append((sx - wid / 2, sy - hgt, sx + wid / 2, sy, 0xFF40FF40))
            struct.pack_into("<IIQ", buf, 0, MAGIC, len(boxes), frame)
            for i, (x0, y0, x1, y1, col) in enumerate(boxes[:256]):
                struct.pack_into("<ffffII", buf, 16 + i * 24, x0, y0, x1, y1, col, 0)
            frame += 1
            if frame % 30 == 0:
                out("frame %d boxes=%d yaw=%.1f pitch=%.1f" % (frame, len(boxes), yaw, pitch))
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

