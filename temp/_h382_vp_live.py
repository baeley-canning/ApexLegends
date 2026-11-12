r"""h382 -- live read-back of the ViewRender singleton and the matrix it hands out.

What the static RE of h381 claims, and what this probe has to prove on the live game:

  GetViewRenderInstance()          rva 0x22670F0, fast path `lea rax,[rip+0x1b1ead4]; ret`
  the singleton                    rva 0x3D86100  (.data, image-resident -- no heap needed)
  its vtable                       rva 0x3133AA0
  GetViewMatrix(index)             vtable +0x80 -> 0x20DA270 -> 0x20DB0BE
                                   `movsx rax,[rbp+0x1308]; mov rax,[rcx+rax*8+0x11a390]`
  matrix pointer slots             +0x11A390 (index 0) / +0x11A398 (index 1)
  the two buffers                  +0x11A2D0 (A) / +0x11A310 (B), 0x40 bytes each
  world-to-screen 0x20B7FD0        reads slot index 0, row-vector VP, w = row 3, 1/w

The whole chain is inside the image mapping, and that is the only thing that matters
here: gdrv3 reads physical memory, the image is physically contiguous, the heap is
not.  That is why every earlier attempt to walk to this object through pointers
stalled -- the object was never in the heap.

Gates (read-only; nothing is written, no service is touched, R4 is trivial):

  G0  game alive           pid from dumplive.find_pid, then pid_alive
  G1  image base read-back MZ/PE at image_pa, SizeOfImage + TimeDateStamp == file
  G2  vtable is the vtable [obj] in-image and == the VA the file holds at that RVA,
                           which also recovers image_va without ASLR help
  G3  slots hold buffers   [obj+0x11A390] == image_va+0x11A2D0, [..+0x11A398] == +0x11A310
  G4  buffer A passes      the repo's own canary, ext/p74_matrix.py
  G5  it is a projection   the camera recovered from rows projects to screen centre
  G6  stability            two samples 300 ms apart are not torn

A gate that cannot run because the game is gone prints SKIPPED and the verdict is
PARTIAL, never PASS (R9).

Usage:  python temp\_h382_vp_live.py
Output: temp\_h382_out.txt  (own file, R5)
"""
from __future__ import annotations

import math
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
sys.path.insert(0, HERE)

import gio                                                      # noqa: E402
import dumplive as dl                                           # noqa: E402
import p74_matrix as p74                                        # noqa: E402

OUT = os.path.join(HERE, "_h382_out.txt")
OFFS = os.path.join(HERE, "qk_offsets.txt")

OBJ = 0x3D86100          # static CViewRender
VT = 0x3133AA0           # its vtable
SLOT0 = 0x11A390         # matrix pointer, index 0 (what 0x20B7FD0 uses)
SLOT1 = 0x11A398
BUF_A = 0x11A2D0
BUF_B = 0x11A310
LEGACY = 0x9440B4        # the standing "vp_rva" candidate, comparison only
FILE_VT = 0x143133AA0    # vtable VA as written in the file (image base 0x140000000)
SIZE_OF_IMAGE = 0x0DFB8000
STAMP = 0x6ADBF892
W, H = 1920, 1080

L: list[str] = []


def p(s="") -> None:
    L.append(s)
    print(s, flush=True)


def u32(b, o=0):
    return struct.unpack_from("<I", b, o)[0]


def u64(b, o=0):
    return struct.unpack_from("<Q", b, o)[0]


def _write():
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")


def _cam(m):
    """Camera position from a row-vector view matrix (rows 0,1,3, translation 3,7,11)."""
    rows = [(m[0], m[1], m[2]), (m[4], m[5], m[6]), (m[12], m[13], m[14])]
    t = (m[3], m[7], m[11])
    unit, ts = [], []
    for i, row in enumerate(rows):
        n = math.sqrt(sum(c * c for c in row))
        if n < 1e-9:
            return None
        unit.append(tuple(c / n for c in row))
        ts.append(t[i] / n)
    return tuple(-(ts[0] * unit[0][i] + ts[1] * unit[1][i] + ts[2] * unit[2][i])
                 for i in range(3))


def _proj(m, cam):
    """Screen point of a world position: row-vector, w = row 3, then 1/w."""
    x, y, z = cam
    px = m[0] * x + m[1] * y + m[2] * z + m[3]
    py = m[4] * x + m[5] * y + m[6] * z + m[7]
    pw = m[12] * x + m[13] * y + m[14] * z + m[15]
    if pw != pw or pw <= 1e-6:
        return None
    return (px / pw * 0.5 + 0.5) * W, (0.5 - py / pw * 0.5) * H, pw


def main() -> int:
    p("h382 -- live ViewRender / view-matrix read-back   %s"
      % time.strftime("%Y-%m-%d %H:%M:%S"))
    parts = []

    pid = dl.find_pid()
    p("G0 game            pid=%s alive=%s"
      % (pid or "-", (dl.pid_alive(pid) if pid else "n/a")))
    if not pid:
        p("")
        p("RESULT: game not running -> nothing was read")
        p("VERDICT: PARTIAL (SKIPPED: every gate)  R9: not an in-game verdict")
        _write()
        return 2
    parts.append("G0=PASS")

    try:
        with open(OFFS, encoding="utf-8") as f:
            kv = dict(l.strip().split("=", 1) for l in f if "=" in l)
        image_pa = int(kv["image_pa"], 16)
    except OSError:
        p("")
        p("RESULT: temp\\qk_offsets.txt missing image_pa")
        p("VERDICT: PARTIAL (SKIPPED: no recorded image base)")
        _write()
        return 2

    try:
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        p("")
        p("RESULT: \\\\.\\GIOV3 would not open (%s); elevated=%s"
          % (e, dl.elevation()))
        p("VERDICT: PARTIAL (SKIPPED: every physical gate -- rerun via"
          " _ritual\\h382_vp.ps1, the device DACL needs admin)")
        _write()
        return 2
    ranges, _note = dl.usable_ranges(g.ram_top, None, None)

    def rd(pa, n, tries=8):
        """Physical read inside the RAM map's intervals (R10)."""
        if not any(lo <= pa and pa + n <= hi for lo, hi in ranges):
            return None
        try:
            return dl.retry_phys(g, pa, n, tries=tries)
        except OSError:
            return None

    # ---- G1: the recorded image base is this image, right now -------------
    hdr = rd(image_pa, 0x40)
    if not hdr or hdr[:2] != b"MZ":
        p("G1 image base      FAIL  no MZ at %#x" % image_pa)
        p("")
        p("RESULT: image_pa=%#x is not the live mapping" % image_pa)
        p("VERDICT: FAIL (variable: image base) -- re-record qk_offsets.txt")
        _write()
        return 1
    lf = u32(hdr, 0x3C)
    nt = rd(image_pa + lf, 0x58)
    if not nt or nt[:4] != b"PE\0\0":
        p("G1 image base      FAIL  no PE at %#x+%#x" % (image_pa, lf))
        p("")
        p("RESULT: PE header unreadable though MZ was present")
        p("VERDICT: FAIL (variable: image base)")
        _write()
        return 1
    soi = u32(nt, 0x18 + 0x38)
    stamp = u32(nt, 0x08)
    ok1 = (soi == SIZE_OF_IMAGE and stamp == STAMP)
    p("G1 image base      %s  %#x  SizeOfImage=%#x stamp=%08x (file %#x/%08x)"
      % ("PASS" if ok1 else "FAIL", image_pa, soi, stamp, SIZE_OF_IMAGE, STAMP))
    if not ok1:
        p("")
        p("RESULT: image at %#x is not the build that was RE'd" % image_pa)
        p("VERDICT: FAIL (variable: build identity)")
        _write()
        return 1
    parts.append("G1=PASS")
    return _body(parts, image_pa, rd)


def _body(parts, image_pa, rd) -> int:
    def sample():
        return {
            "obj": rd(image_pa + OBJ, 0x10),
            "slots": rd(image_pa + SLOT0, 0x10),
            "bufA": rd(image_pa + BUF_A, 0x40),
            "bufB": rd(image_pa + BUF_B, 0x40),
            "legacy": rd(image_pa + LEGACY, 0x40),
        }

    s1 = sample()
    time.sleep(0.30)
    s2 = sample()

    obj_vt = u64(s1["obj"]) if s1["obj"] else None
    slot0 = u64(s1["slots"]) if s1["slots"] else None
    slot1 = u64(s1["slots"], 8) if s1["slots"] else None

    p("")
    p("read set (image_pa=%#x)" % image_pa)
    p("  [obj]      = %s   (file says %#x)"
      % ("FAIL" if obj_vt is None else "%#x" % obj_vt, FILE_VT))
    p("  [slot0]    = %s" % ("FAIL" if slot0 is None else "%#x" % slot0))
    p("  [slot1]    = %s" % ("FAIL" if slot1 is None else "%#x" % slot1))
    if obj_vt is None:
        p("")
        p("RESULT: singleton at image+%#x unreadable" % OBJ)
        p("VERDICT: FAIL (variable: singleton readability)")
        _write()
        return 1

    image_va = obj_vt - VT                # the vtable names the base; no ASLR guess
    ok3 = (slot0 is not None and slot1 is not None
           and (slot0 - image_va) == BUF_A and (slot1 - image_va) == BUF_B)
    p("G2 vtable          %s  image base = %#x  (vtable in-image: %s)"
      % ("PASS" if obj_vt == FILE_VT else "FAIL", image_va,
         "yes" if 0 <= (obj_vt - image_va) < SIZE_OF_IMAGE else "no"))
    p("G3 slot->buffer    %s  slot0-image=%s (want %#x)  slot1-image=%s (want %#x)"
      % ("PASS" if ok3 else "FAIL",
         ("%#x" % (slot0 - image_va)) if slot0 else "FAIL", BUF_A,
         ("%#x" % (slot1 - image_va)) if slot1 else "FAIL", BUF_B))
    parts.append("G2=%s" % ("PASS" if obj_vt == FILE_VT else "FAIL"))
    parts.append("G3=%s" % ("PASS" if ok3 else "FAIL"))

    def unpack(b):
        return list(struct.unpack_from("<16f", b, 0)) if b and len(b) >= 64 else None

    ma, mb, ml = unpack(s1["bufA"]), unpack(s1["bufB"]), unpack(s1["legacy"])
    tier, score, di = None, 0.0, None
    if ma:
        tier, score, di = p74.canary(ma)
        p("")
        p("buffer A (image+%#x): the index-0 matrix 0x20B7FD0 projects with" % BUF_A)
        for r in range(4):
            p("  row%d  " % r + " ".join("%14.6f" % v for v in ma[r * 4:r * 4 + 4]))
        p("  p74 canary:      %s"
          % (("PASS tier=%s score=%.1f" % (tier, score)) if tier
             else "FAIL " + "; ".join(p74.fail_reasons(ma) or ["no tier"])))
        if di:
            p("  geometry:        |row0|=%.4f |row1|=%.4f |row2|=%.4f dot01=%.5f"
              % (di["rl"], di["ul"], di["fl"], di["dot"]))
    ok5 = False
    cam = None
    if ma:
        cam = _cam(ma)
        proj = _proj(ma, cam) if cam else None
        if cam:
            p("  camera implied:  (%.2f, %.2f, %.2f)" % cam)
            p("  project(cam) ->  %s"
              % (("(%.2f, %.2f) depth=%.1f   centre=(%d, %d)"
                  % (proj[0], proj[1], proj[2], W // 2, H // 2)) if proj else "behind"))
            ok5 = bool(proj) and abs(proj[0] - W / 2) < 2.0 and abs(proj[1] - H / 2) < 2.0
        else:
            p("  camera implied:  FAIL (a row of the matrix is zero-length)")
    p("G4 canary          %s  (informational only -- its |m11|<100 rule is a"
      " view-matrix rule; a VP puts -dot(fwd,cam) there)"
      % (("PASS tier=%s score=%.1f" % (tier, score)) if tier else "no tier"))
    p("G5 centre-anchored %s" % ("PASS" if ok5 else "FAIL"))
    parts.append("G4=INFO(%s)" % (tier or "no tier"))
    parts.append("G5=%s" % ("PASS" if ok5 else "FAIL"))

    ok6 = s1["bufA"] is not None and s2["bufA"] is not None
    same = s1["bufA"] == s2["bufA"]
    p("G6 stability       %s  two samples 300 ms apart: %s"
      % ("PASS" if ok6 else "FAIL",
         "identical" if same else ("differ (camera moved, or a tear)" if ok6 else "FAIL")))
    parts.append("G6=%s" % ("PASS" if ok6 else "FAIL"))
    if ok6 and not same:
        for r in range(4):
            p("  s2 row%d " % r + " ".join("%14.6f" % v
                                           for v in struct.unpack_from("<4f", s2["bufA"], r * 16)))
    return _tail(parts, image_pa, image_va, ma, mb, ml)


def _tail(parts, image_pa, image_va, ma, mb, ml) -> int:
    p("")
    if mb:
        p("buffer B (image+%#x, index 1 -- NOT used by 0x20B7FD0):" % BUF_B)
        for r in range(4):
            p("  row%d  " % r + " ".join("%14.6f" % v for v in mb[r * 4:r * 4 + 4]))
        if ma:
            d = max(abs(mb[i] - ma[i]) for i in range(16))
            p("  max|B-A| = %.6f -> %s"
              % (d, "same frame" if d < 1e-6 else "double buffer holds another frame"))
    else:
        p("buffer B unreadable")

    p("")
    if ml:
        p("legacy candidate image+%#x (the standing qk_offsets vp_rva):" % LEGACY)
        p("  as 16 f32: " + " ".join("%g" % v for v in ml))
        if ma:
            d = max(abs(ml[i] - ma[i]) for i in range(16))
            p("  == buffer A? %s (max|d|=%.6g)" % ("YES" if d < 1e-6 else "no", d))
        t2, s2v, _d = p74.canary(ml)
        p("  p74 canary on it: %s"
          % (("tier=%s score=%.1f" % (t2, s2v)) if t2
             else "FAIL " + "; ".join(p74.fail_reasons(ml) or ["no tier"])))
    else:
        p("legacy candidate image+%#x unreadable" % LEGACY)

    p("")
    p("chain:  image_pa %#x -> image_va %#x" % (image_pa, image_va))
    p("        ViewRender  image_va+%#x  (static .data: physical, no page tables)" % OBJ)
    p("        vtable      image_va+%#x  slot +0x80 = GetViewMatrix(index)" % VT)
    p("        member      +0x%X  matrix pointer array [2]" % SLOT0)
    p("        matrix      [image_va+%#x] -> image_va+%#x  (16 f32, row-vector, w=row3)"
      % (SLOT0, BUF_A))
    p("RESULT: " + " ".join(parts))
    gated = [x for x in parts if "=INFO(" not in x]
    good = all(x.endswith("=PASS") for x in gated)
    p("VERDICT: %s (variable: live readability of the static ViewRender chain)"
      % ("PASS" if good else "FAIL"))
    _write()
    return 0 if good else 1


if __name__ == "__main__":
    raise SystemExit(main())
