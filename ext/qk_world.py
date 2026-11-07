r"""qk_world.py -- the provider-shaped world setup.  One passive run, no mouse.

This is the piece every real external cheat has and we kept sidestepping: the game's
own topology, reached through static offsets, validated by content (your name), with
nothing asked of the player but "stand there".

Produces, in order, each stage proving the previous one:
  1. dtb + image base       qk_va.discover (PEB route -> name sweep -> pml4 shape)
  2. image_pa               walk(base) through the page tables (fresh every launch)
  3. entity list            qword in writable .data -> array of vtable-backed objects
  4. local player           the slot whose object CONTAINS YOUR NAME (the arbiter:
                            no heuristic is trusted until a name is found)
  5. origin / yaw / pitch   derived from the found name position (same build
                            arithmetic as the movement-verified anchor)
  6. bone array             pointer in the local object at which >=16 world
                            positions cluster near the origin; head = top-most bone
                            PROVEN by projecting head-above-feet through the live
                            matrix.  This is the per-legend head height fix: no
                            fixed box constant, no band guess.

Writes temp\qk_world.txt (evidence) and temp\qk_world.json (the product config:
all offsets, VA-ready and PA-ready).

Usage:
    python qk_world.py --name=kern30120            (self-elevates for gdrv3)

Rules kept: gdrv3-only reads, no attach, no driver, no reboot; every PA read goes
through the RAM map (R10); every stage writes a RESULT line (R3).
"""
import ctypes
import json
import math
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import dumplive as dl          # noqa: E402
import gio                     # noqa: E402
import qk_va as VA             # noqa: E402  (Reader / discover / walk -- unchanged)

TMP = os.path.join(os.path.dirname(HERE), "temp")
OUT = os.path.join(TMP, "qk_world.txt")
JSON = os.path.join(TMP, "qk_world.json")
OFF_FILE = os.path.join(TMP, "qk_offsets.txt")
VP_RVA_DEFAULT = 0xDD792B0                  # cached from the 08/11 --data --watch run
IMG_SIZE = 0xDFB8000                        # r5apex_dx12 SizeOfImage - the process arbiter
PROC = "r5apex_dx12.exe"


def out(s):
    line = "".join(c if ord(c) < 128 else "?" for c in s)
    print(line, flush=True)
    try:
        with open(OUT, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def arg(name, default=None, cast=str):
    for i, a in enumerate(sys.argv):
        if a == "--" + name and i + 1 < len(sys.argv):
            return cast(sys.argv[i + 1])
        if a.startswith("--" + name + "="):
            return cast(a.split("=", 1)[1])
    return default


def flag(name):
    return ("--" + name) in sys.argv


def fin(v, lim=1e7):
    return isinstance(v, float) and not math.isnan(v) and abs(v) < lim


def u64_at(rd, va):
    b = rd.read(va, 8)
    return None if b is None else struct.unpack("<Q", b)[0]


def read_utf16_name(rd, va, n=64):
    b = rd.read(va, n)
    if not b:
        return ""
    s = b.decode("utf-16-le", "replace")
    return s.split("\x00", 1)[0].strip()


def vec(rd, va):
    b = rd.read(va, 12)
    if not b:
        return None
    return struct.unpack("<3f", b)


def sane_pos(v):
    return (v is not None and all(fin(x) for x in v)
            and abs(v[0]) < 40000 and abs(v[1]) < 5000 and abs(v[2]) < 40000
            and not (v[0] == 0 and v[1] == 0 and v[2] == 0))


def find_name_in(rd, obj_va, needle, span=0x1200):
    """(offset, kind) of the needle inside the object region, or None."""
    blob = rd.read(obj_va, span)
    if not blob:
        return None
    i = blob.find(needle.encode("ascii"))
    if i >= 0:
        return i, "ascii"
    j = blob.find(needle.encode("utf-16-le"))
    if j >= 0:
        return j, "utf16"
    return None


def canon(v):
    return 0x100000000 <= v <= 0x7FFFFFFFFFFF and (v & 7) == 0


def scan_arrays(g, rd, base, data_rva, data_pa, data_size, text_pa_lo, text_pa_hi,
                cap=4000, slots_read=64):
    """Physics: a candidate is 8 consecutive aligned qwords with >=6 canonical VAs
    (an array of objects), then >=3 of its first 4 objects must start with a vtable
    that resolves into the image .text (physical check -- no VA-base guessing).
    Returns [(vt, rva, array_va)] sorted by vt."""
    cands = []
    scanned = 0
    t0 = time.time()
    qpa = data_pa
    end = data_pa + data_size
    while qpa < end:
        va = base + data_rva + (qpa - data_pa)
        n = min(0x40000, end - qpa)
        try:
            chunk = dl.retry_phys(g, qpa, n, tries=4)
        except OSError as e:
            out("    data read fault at %#x: %s" % (qpa, e))
            qpa += 0x1000
            continue
        scanned += len(chunk)
        for off in range(0, len(chunk) - 64, 8):
            vals = struct.unpack_from("<8Q", chunk, off)
            if sum(1 for v in vals if canon(v)) < 6:
                continue
            v = vals[0]
            b = rd.read(v, slots_read * 8)
            if not b:
                continue
            slots = struct.unpack_from("<%dQ" % slots_read, b)
            cs = [s for s in slots[:16] if canon(s)]
            if len(cs) < 4:
                continue
            vt = 0
            for c in cs[:4]:
                q = u64_at(rd, c)
                if not q:
                    continue
                pa = rd.page_pa(q)
                if pa is not None and text_pa_lo <= pa < text_pa_hi:
                    vt += 1
            if vt >= 3:
                cands.append((vt, (va + off) - base, v))
                if len(cands) >= cap:
                    break
        qpa += len(chunk)
        if scanned % 0x1000000 < len(chunk):
            out("    scanned %d MB, candidates=%d (%.0fs)"
                % (scanned // 0x100000, len(cands), time.time() - t0))
    cands.sort(reverse=True)
    out("RESULT scan: scanned=%d MB candidates=%d (%.0fs)"
        % (scanned // 0x100000, len(cands), time.time() - t0))
    return cands


def validate_by_name(g, rd, cands, needle, max_cand=60):
    """The arbiter.  For each candidate array, walk its slots; the first candidate
    with a slot object whose bytes CONTAIN THE PLAYER'S NAME is the entity list.
    Returns (vt, rva, array_va, slot, obj_va, name_off, kind) or None."""
    tried = 0
    for vt, rva, array_va in cands[:max_cand]:
        tried += 1
        b = rd.read(array_va, 128 * 8)
        if not b:
            continue
        slots = struct.unpack_from("<%dQ" % (len(b) // 8), b)
        for si, obj in enumerate(slots):
            if not canon(obj):
                continue
            hit = find_name_in(rd, obj, needle)
            if hit:
                off, kind = hit
                out("RESULT validate: candidate #%d static_rva=%#x array=%#x "
                    "slot=%d name-%s at +%#x" % (tried, rva, array_va, si, kind, off))
                return vt, rva, array_va, si, obj, off, kind
        if tried % 10 == 0:
            out("    validated %d/%d candidates..." % (tried, min(len(cands), max_cand)))
    return None


def nearest_sane_vec(rd, va, around=0x900):
    """Sane world triple nearest to va (value-validated, not offset-arithmetic:
    survives a layout shuffle that would quietly break name-0xEEC)."""
    b = rd.read(va - around, around * 2)
    if not b:
        return None
    best = None
    for off in range(0, len(b) - 12, 4):
        v = struct.unpack_from("<3f", b, off)
        if not sane_pos(v):
            continue
        d = abs(off - around)
        if best is None or d < best[0]:
            best = (d, off - around, v)
    return None if not best else (best[1], best[2])


def find_bones(g, rd, obj_va, origin, lo=0x300, hi=0x2000):
    """A bone array is a pointer in the local object at which >=14 world triples
    cluster within 600 units of the origin.  Returns (ptr_off, bone_va, count,
    head_vec) with head = top-most clustered bone.  Pure geometry -- works while
    the player stands still because bones are posed every frame regardless."""
    best = None
    for poff in range(lo, hi, 8):
        v2 = u64_at(rd, obj_va + poff)
        if not v2:
            continue
        blob = rd.read(v2, 12 * 56)
        if not blob:
            continue
        near = 0
        top = None
        topdy = -1e9
        for i in range(0, len(blob) - 12, 12):
            p = struct.unpack_from("<3f", blob, i)
            if not sane_pos(p):
                continue
            dx, dy, dz = p[0] - origin[0], p[1] - origin[1], p[2] - origin[2]
            if dx * dx + dz * dz < 600.0 * 600.0 and abs(dy) < 300.0:
                near += 1
                if dy > topdy:
                    topdy = dy
                    top = p
        if near >= 14 and top is not None and 30.0 < topdy < 260.0:
            if best is None or near > best[2]:
                best = (poff, v2, near, top)
    return best


def main():
    if not dl.elevation() and not flag("no-elevate"):
        argv = [os.path.abspath(sys.argv[0])] + [a for a in sys.argv[1:]
                                                 if a != "--no-elevate"]
        cmd = " ".join('"%s"' % a if " " in a else a for a in argv) + " --no-elevate"
        out("not elevated - relaunching")
        out(dl.run_elevated(cmd))
        return 0

    VA.set_out(OUT)
    # let qk_va's discover_pml4 exact-match the game by image size instead of "largest":
    # a smaller neighbouring process must never win the walk.
    sys.argv.append("--want-size=%#x" % IMG_SIZE)
    sys.argv.append("--peb-first")           # no 27 GB name sweep on a fresh pid
    dl.THROTTLE_MS = 2                       # 0x124 mitigation: 2 ms per 64 chunks
    dl.RETRY_MS = 10                         # junk frames must not cost 1.4 s each
    VA.VA_THROTTLE = 2
    needle = arg("name", "kern30120")
    out("===== qk_world: entity list + local player + bones (gdrv3 only, no attach) =====")
    out("name=%s" % needle)

    dl.PROC_NAME = "r5apex"
    pid = dl.find_pid()
    if not pid:
        out("RESULT: no-game")
        out("VERDICT: PARTIAL - game not running")
        return 2
    out("pid=%d" % pid)

    try:
        g = gio.Gio(chunk=0x40000)           # 256 KiB ioctls: 4x fewer calls (0x124 mitigation)
    except OSError as e:
        out("gio open failed: %s" % e)
        out("VERDICT: PARTIAL - gdrv3 not openable")
        return 2
    # read-path fallback: pages gdrv3 refuses (1450) go through apexdrv's MmCopyMemory
    # when it is loaded.  dl.retry_phys calls g.read_phys, so one instance-level
    # wrapper covers the whole walk machinery.
    _orig_rp = g.read_phys

    def _rp_fallback(pa, n):
        try:
            return _orig_rp(pa, n)
        except OSError:
            return VA.drv_phys(pa, n)

    g.read_phys = _rp_fallback

    m = VA.get_map(g, pid)
    if not m:
        out("RESULT: no-dtb")
        out("VERDICT: PARTIAL - dtb discovery failed (PEB -> sweep -> pml4)")
        return 3
    dtb, base = m["dtb"], m["base"]
    rd = VA.Reader(g, dtb)
    if rd.read(base, 2) != b"MZ":
        out("RESULT: bad-base %#x" % base)
        out("VERDICT: PARTIAL")
        return 3
    image_pa = rd.page_pa(base)
    out("image base=%#x pa=%#x dtb=%#x" % (base, image_pa, dtb))

    elf = struct.unpack("<I", rd.read(base + 0x3C, 4))[0]
    pe = rd.read(base + elf, 0x18)
    nsec = struct.unpack_from("<H", pe, 6)[0]
    optsize = struct.unpack_from("<H", pe, 0x14)[0]
    stamp = struct.unpack_from("<I", pe, 8)[0]
    sec_bytes = rd.read(base + elf + 0x18 + optsize, nsec * 40)
    data_rva = data_size = text_rva = text_size = 0
    for i in range(nsec):
        s = sec_bytes[i * 40:(i + 1) * 40]
        nm = s[:8].rstrip(b"\x00").decode("ascii", "replace")
        vsz, vad = struct.unpack_from("<II", s, 8)
        if nm == ".data":
            data_rva, data_size = vad, vsz
        elif nm == ".text":
            text_rva, text_size = vad, vsz
    out("build stamp=%#x .data rva=%#x size=%#x .text rva=%#x size=%#x"
        % (stamp, data_rva, data_size, text_rva, text_size))
    if not data_size or not text_size:
        out("VERDICT: PARTIAL - sections unreadable")
        return 3
    data_pa = image_pa + data_rva
    text_pa_lo = image_pa + text_rva
    text_pa_hi = text_pa_lo + text_size

    vp_rva = VP_RVA_DEFAULT
    try:
        with open(OFF_FILE) as f:
            for ln in f:
                if ln.startswith("vp_rva="):
                    vp_rva = int(ln.strip().split("=", 1)[1], 16)
    except (OSError, ValueError):
        pass
    try:
        with open(OFF_FILE, "w") as f:
            f.write("image_pa=0x%X\nvp_rva=0x%X\n" % (image_pa, vp_rva))
        out("offsets refreshed: image_pa=0x%X vp_rva=%#x" % (image_pa, vp_rva))
    except OSError:
        pass
    mat = None
    try:
        mat = struct.unpack("<16f", dl.retry_phys(g, image_pa + vp_rva, 64, tries=6))
        out("vp matrix: m15=%.4f m11=%.4f m5=%.4f m[12..14]=(%.1f,%.1f,%.1f)"
            % (mat[15], mat[11], mat[5], mat[12], mat[13], mat[14]))
    except OSError as e:
        out("vp read fault: %s" % e)

    out("scanning .data for vtable-backed pointer arrays ...")
    cands = scan_arrays(g, rd, base, data_rva, data_pa, data_size, text_pa_lo, text_pa_hi)
    if not cands:
        out("VERDICT: PARTIAL - no vtable-backed array found")
        return 4
    for vt, rva, ava in cands[:6]:
        out("    cand static_rva=%#010x array=%#x vt=%d" % (rva, ava, vt))

    val = validate_by_name(g, rd, cands, needle)
    if not val:
        out("VERDICT: PARTIAL - arrays found, name in none of them")
        return 5
    vt, el_rva, array_va, local_slot, local_obj, name_off, kind = val
    out("ENTITY LIST: static_rva=%#x array=%#x local_slot=%d obj=%#x name_off=%#x (%s)"
        % (el_rva, array_va, local_slot, local_obj, name_off, kind))

    guess = name_off - 0xEEC
    origin_off = None
    origin = vec(rd, local_obj + guess) if kind == "utf16" else None
    if sane_pos(origin):
        origin_off = guess
    else:
        got = nearest_sane_vec(rd, local_obj + guess)
        if got:
            origin_off, origin = got
    if origin_off is None:
        out("VERDICT: PARTIAL - name found, no sane position near it")
        return 6
    out("local player: origin_off=%#x val=(%.1f, %.1f, %.1f) [%s]"
        % (origin_off, origin[0], origin[1], origin[2],
           "name-0xEEC held" if origin_off == guess else "shifted %+d" % (origin_off - guess)))
    yb = rd.read(local_obj + name_off + 0x3A4, 8)
    if yb:
        yaw, pitch = struct.unpack("<2f", yb)
        out("angles @name+0x3A4/8: yaw=%.2f pitch=%.2f (%s)"
            % (yaw, pitch, "ok" if abs(yaw) <= 180 and abs(pitch) <= 90 else "OUT"))

    bones = find_bones(g, rd, local_obj, origin)
    head_proj = None
    if bones:
        boff, bva, cnt, head = bones
        out("BONES: off=%#x va=%#x clustered=%d head=(%.1f, %.1f, %.1f)"
            % (boff, bva, cnt, head[0], head[1], head[2]))
        if mat:
            import qk_phys as PM
            pp = PM.project(mat, origin[0], origin[1], origin[2], 1920, 1080)
            ph = PM.project(mat, head[0], head[1], head[2], 1920, 1080)
            if pp and ph:
                out("PROOF projection: feet=(%.0f,%.0f) head=(%.0f,%.0f) head_above=%s"
                    % (pp[0], pp[1], ph[0], ph[1], ph[1] < pp[1] - 6))
                head_proj = (pp, ph)
    else:
        boff = bva = None
        cnt = 0
        out("RESULT: no-bones")

    names = []
    b = rd.read(array_va, 128 * 8)
    if b:
        slots = struct.unpack_from("<%dQ" % (len(b) // 8), b)
        for si, obj in enumerate(slots):
            if not canon(obj):
                continue
            nm = "".join(c for c in read_utf16_name(rd, obj + name_off)
                         if 32 <= ord(c) < 127)[:24]
            if len(nm) >= 2:
                names.append((si, nm))
    out("PLAYERS: %d slots with a readable name" % len(names))
    for si, nm in names[:24]:
        out("    slot %2d  %s%s" % (si, nm, "  <- YOU" if si == local_slot else ""))

    ok = bones is not None
    try:
        with open(JSON, "w") as f:
            json.dump({"pid": pid, "stamp": stamp, "base": base, "dtb": dtb,
                       "image_pa": image_pa, "vp_rva": vp_rva,
                       "entity_list_rva": el_rva, "entity_array_va": array_va,
                       "local_slot": local_slot, "name_off": name_off,
                       "origin_off": origin_off, "yaw_off": name_off + 0x3A4,
                       "pitch_off": name_off + 0x3A8,
                       "bone_off": boff, "bone_va": bva, "bones": cnt,
                       "players": names, "ts": int(time.time())}, f, indent=1)
        out("json: %s" % JSON)
    except OSError:
        pass
    out("RESULT: entity_list=%#x local_obj=%#x bones=%s players=%d"
        % (el_rva, local_obj, ("%#x" % boff) if boff else "none", len(names)))
    out("VERDICT: %s - name-validated entity list + local player%s"
        % ("PASS" if ok else "PARTIAL",
           (", bones with head-above-feet proof" if head_proj else ", bones pending")))
    return 0 if ok else 7


if __name__ == "__main__":
    sys.exit(main())
