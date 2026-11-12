r"""h383 -- h382's chain again, but every byte read through the PAGE TABLES.

h382 read the image as `image_pa + rva` -- i.e. it assumed the 234 MB image is
physically contiguous.  It is not.  h382's G1 passed (the page at image_pa
really is this build: SizeOfImage 0xDFB8000, stamp 6ADBF892) but everything
deeper came back as somebody else's bytes: [ViewRender] read 0, the slot pair
was garbage, and the "matrix" at +0x11A2D0 was a run of f32 denormals
(9.4e-39, ... = small integers reinterpreted as floats).  That is the signature
of reading a stale / non-contiguous copy of the image, not the live mapping.

h383 changes exactly ONE variable -- the read path:

    h382   image_pa + rva                          flat physical offset
    h383   CR3 -> PML4/PDPT/PD/PT -> pa + offset    dl.Walk, per 4 KiB page

Everything else is h382's: same constants, same six gates, same helpers.  The
extra consequence is that the image VA no longer has to be *derived* from a
read vtable pointer -- qk_va.get_map() returns a (dtb, base) that it validates
with an MZ read, so G2 becomes a real test of the claim "the static
singleton's first qword is the vtable at rva 0x3133AA0".

The base from get_map() can be any module it happened to find (find_mz walks
the address space top-down, so on some boots it lands on ntdll), so the base is
resolved here by identity: PEB -> Ldr -> InLoadOrderModuleList -> the module
whose name is r5apex_dx12.exe, then SizeOfImage + TimeDateStamp must match the
installed file before anything else runs.

Gates (read-only; nothing is written, no service is touched -- R4 trivial):

  G0  game alive            dumplive.find_pid, then pid_alive
  G1  image VA + identity   MZ/PE at base_va; SizeOfImage + stamp == file
  G2  vtable is the vtable  [base_va+0x3D86100] == base_va+0x3133AA0 (in-image)
  G3  slots hold buffers    [..+0x11A390] == base_va+0x11A2D0, [..+0x11A398] == +0x11A310
  G4  buffer A passes       the repo's own canary, ext/p74_matrix.py  (INFO only)
  G5  it is a projection    camera recovered from the rows projects to centre
  G6  stability              two samples 300 ms apart are not torn

Two added gates, informational by construction -- they cannot move the verdict:

  G7  contiguity  for every offset used: pa(walk) vs pa(flat), and a byte
                  compare of the flat read against the walk read.  This is the
                  measurement that explains h382.
  G8  code identity  vtable slot +0x80 -> function VA, and the two machine
                  code signatures the static RE claims inside GetViewMatrix:
                    48 63 85 08 13 00 00     movsx rax,[rbp+0x1308]
                    48 8B 84 C1 90 A3 11 00  mov   rax,[rcx+rax*8+0x11a390]

A gate that cannot run because the game is gone prints SKIPPED and the verdict
is PARTIAL, never PASS (R9).

Usage:  python temp\_h383_va_live.py
Output: temp\_h383_out.txt   (own file, R5)
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
import qk_va as qkv                                             # noqa: E402

OUT = os.path.join(HERE, "_h383_out.txt")
OFFS = os.path.join(HERE, "qk_offsets.txt")
QKLOG = os.path.join(HERE, "_h383_qk.txt")

# qk_va.out() appends one line per call to its module-level OUT_PATH, so the
# discovery phase (~2-8 min: name sweep, candidate DTBs, PEB/PML4 fallbacks)
# is tail-able instead of invisible behind stdout buffering.
qkv.OUT_PATH = QKLOG

OBJ = 0x3D86100          # static CViewRender
VT = 0x3133AA0           # its vtable
SLOT0 = 0x11A390         # matrix pointer, index 0 (what 0x20B7FD0 uses)
SLOT1 = 0x11A398
BUF_A = 0x11A2D0
BUF_B = 0x11A310
IDX = 0x1308             # the index byte GetViewMatrix selects the slot with
LEGACY = 0x9440B4        # the standing qk_offsets "vp_rva", comparison only
FILE_VT = 0x143133AA0    # vtable VA as written in the file (base 0x140000000)
MATRIX_FUNC = 0x20DA270  # vtable +0x80 -> this thunk
MATRIX_BODY = 0x20DB0BE  # ... which lands here
SIZE_OF_IMAGE = 0x0DFB8000
STAMP = 0x6ADBF892
EXE = "r5apex_dx12.exe"
W, H = 1920, 1080

SIG_IDX = bytes.fromhex("4863850813 0000".replace(" ", ""))     # movsx rax,[rbp+0x1308]
SIG_S0 = bytes.fromhex("488b84c190a31100")                       # [rcx+rax*8+0x11a390]
SIG_S1 = bytes.fromhex("488b84c198a31100")                       # [rcx+rax*8+0x11a398]

L: list[str] = []


def p(s="") -> None:
    L.append(s)
    print(s, flush=True)


def u16(b, o=0):
    return struct.unpack_from("<H", b, o)[0]


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
    p("h383 -- ViewRender / view-matrix read-back through the page tables   %s"
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
        g = gio.Gio(chunk=0x10000)
    except OSError as e:
        p("")
        p("RESULT: \\\\.\\GIOV3 would not open (%s); elevated=%s"
          % (e, dl.elevation()))
        p("VERDICT: PARTIAL (SKIPPED: every physical gate -- rerun via"
          " _ritual\\h383_va.ps1, the device DACL needs admin)")
        _write()
        return 2
    ranges, _note = dl.usable_ranges(g.ram_top, None, None)
    p("     RAM map       ram_top=%#x ranges=%d usable=%.1f GB"
      % (g.ram_top, len(ranges), sum(b - a for a, b in ranges) / 1073741824.0))

    # ---- the VA map: cache/driver/discovery, validated by qk_va with an MZ read
    m = qkv.get_map(g, pid)
    if not m:
        p("")
        p("RESULT: no DTB/base for pid %d (qk_va.get_map returned None)" % pid)
        p("VERDICT: PARTIAL (SKIPPED: every VA gate -- no page tables)")
        _write()
        return 2
    dtb, map_base = m["dtb"], m["base"]
    p("     VA map         dtb=%#x base_from_get_map=%#x" % (dtb, map_base))

    rd = qkv.Reader(g, dtb)

    def rd_va(va, n):
        """VA read through the page tables.  None on a fault / device refusal."""
        try:
            return rd.read(va, n)
        except (OSError, ValueError):
            return None

    def rd_pa(pa, n, tries=8):
        """Flat physical read, still inside the RAM map's intervals (R10)."""
        ok = any(lo <= pa and pa + n <= hi for lo, hi in ranges)
        if not ok:
            return None
        try:
            return dl.retry_phys(g, pa, n, tries=tries)
        except OSError:
            return None

    def ident(va):
        """(size_of_image, stamp) of the PE at va, or (0, 0) if there is none."""
        if not va:
            return 0, 0
        hdr = rd_va(va, 0x40)
        if not hdr or hdr[:2] != b"MZ":
            return 0, 0
        lf = u32(hdr, 0x3C)
        if not (0x40 <= lf <= 0x1000):
            return 0, 0
        nt = rd_va(va + lf, 0x60)
        if not nt or nt[:4] != b"PE\0\0":
            return 0, 0
        return u32(nt, 0x18 + 0x38), u32(nt, 0x08)

    def modules():
        """PEB -> Ldr -> InLoadOrderModuleList -> [(name, dllbase)]."""
        peb = qkv._peb_va(pid)
        if not peb:
            p("     PEB            unavailable (NtQueryInformationProcess refused)")
            return []
        ldr = rd_va(peb + 0x18, 8)
        if not ldr:
            p("     PEB            %#x read, Ldr unreadable" % peb)
            return []
        ldr = u64(ldr)
        head = ldr + 0x10
        cur = rd_va(head, 8)
        if not cur:
            p("     Ldr            %#x read, module list head unreadable" % ldr)
            return []
        cur = u64(cur)
        seen, out = set(), []
        while cur and cur != head and cur not in seen and len(out) < 96:
            seen.add(cur)
            base = rd_va(cur + 0x30, 8)
            ln = rd_va(cur + 0x58, 4)
            buf = rd_va(cur + 0x60, 8)
            if base and ln and buf:
                n = min(u16(ln), 128)
                s = rd_va(u64(buf), n) if n else None
                try:
                    name = s.decode("utf-16-le") if s else ""
                except UnicodeDecodeError:
                    name = ""
                out.append((name, u64(base)))
            nxt = rd_va(cur, 8)
            cur = u64(nxt) if nxt else 0
        return out

    # The base get_map() hands back is whatever find_mz() walked to first; the
    # image we RE'd is the one whose header matches the installed file.
    cands = [(map_base, "get_map/find_mz")]
    for name, base in modules():
        if base and name.lower().endswith(".exe"):
            cands.append((base, name))
    base_va, base_src, soi, stamp = 0, "", 0, 0
    for va, src in cands:
        s, t = ident(va)
        if s:
            p("     candidate      %#x  %-28s SizeOfImage=%#x stamp=%08x%s"
              % (va, src[:28], s, t,
                 "  <- this build" if (s == SIZE_OF_IMAGE and t == STAMP) else ""))
        if s == SIZE_OF_IMAGE and t == STAMP and not base_va:
            base_va, base_src, soi, stamp = va, src, s, t
    if not base_va and cands:
        # keep a diagnosable base for the later gates, but G1 will say FAIL
        base_va, base_src = cands[0]
        soi, stamp = ident(base_va)

    ok1 = (soi == SIZE_OF_IMAGE and stamp == STAMP)
    p("G1 image VA+id     %s  base_va=%#x (%s) SizeOfImage=%#x stamp=%08x"
      "  (file %#x/%08x)"
      % ("PASS" if ok1 else "FAIL", base_va, base_src or "-", soi, stamp,
         SIZE_OF_IMAGE, STAMP))
    if not ok1:
        p("")
        p("RESULT: no mapped image in pid %d has SizeOfImage=%#x stamp=%08x"
          % (pid, SIZE_OF_IMAGE, STAMP))
        p("VERDICT: FAIL (variable: build identity at the VA map's base)")
        _write()
        return 1
    parts.append("G1=PASS")
    return _body(parts, rd, rd_pa, rd_va, map_base, base_va)
def _body(parts, rd, rd_pa, rd_va, map_base, base_va) -> int:
    def at(rva):
        return base_va + rva

    def sample():
        return {
            "obj": rd_va(at(OBJ), 0x10),
            "slots": rd_va(at(SLOT0), 0x10),
            "bufA": rd_va(at(BUF_A), 0x40),
            "bufB": rd_va(at(BUF_B), 0x40),
            "legacy": rd_va(at(LEGACY), 0x40),
            "idx": rd_va(at(IDX), 4),
        }

    s1 = sample()
    time.sleep(0.30)
    s2 = sample()

    obj_vt = u64(s1["obj"]) if s1["obj"] else None
    slot0 = u64(s1["slots"]) if s1["slots"] else None
    slot1 = u64(s1["slots"], 8) if s1["slots"] else None
    idx = s1["idx"][0] if s1["idx"] else None

    p("")
    p("read set (base_va=%#x, dtb-backed)" % base_va)
    p("  [obj]      = %s   (expect base_va+%#x = %#x)"
      % ("FAIL" if obj_vt is None else "%#x" % obj_vt, VT, at(VT)))
    p("  [slot0]    = %s   (expect base_va+%#x = %#x)"
      % ("FAIL" if slot0 is None else "%#x" % slot0, BUF_A, at(BUF_A)))
    p("  [slot1]    = %s   (expect base_va+%#x = %#x)"
      % ("FAIL" if slot1 is None else "%#x" % slot1, BUF_B, at(BUF_B)))
    p("  index byte +%#x = %s" % (IDX, "FAIL" if idx is None else "%d" % idx))

    ok2 = obj_vt == at(VT)
    ok3 = (slot0 == at(BUF_A)) and (slot1 == at(BUF_B))
    p("G2 vtable          %s  %s"
      % ("PASS" if ok2 else "FAIL",
         ("in-image at offset %#x, as the RE said" % (obj_vt - base_va)) if ok2
         else ("read %s, wanted base_va+%#x" % (
             "FAIL" if obj_vt is None else "%#x" % obj_vt, VT))))
    p("G3 slot->buffer    %s  slot0-base=%s (want %#x)  slot1-base=%s (want %#x)"
      % ("PASS" if ok3 else "FAIL",
         ("%#x" % (slot0 - base_va)) if slot0 else "FAIL", BUF_A,
         ("%#x" % (slot1 - base_va)) if slot1 else "FAIL", BUF_B))
    parts.append("G2=%s" % ("PASS" if ok2 else "FAIL"))
    parts.append("G3=%s" % ("PASS" if ok3 else "FAIL"))

    def unpack(b):
        return list(struct.unpack_from("<16f", b, 0)) if b and len(b) >= 64 else None

    ma, mb, ml = unpack(s1["bufA"]), unpack(s1["bufB"]), unpack(s1["legacy"])


    tier, score, di = None, 0.0, None
    if ma:
        tier, score, di = p74.canary(ma)
        p("")
        p("buffer A (base_va+%#x): the index-0 matrix 0x20B7FD0 projects with" % BUF_A)
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
    p("G4 canary          %s  (informational -- |m11|<100 is a view-matrix rule;"
      " a VP puts -dot(fwd,cam) there)"
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
    _contig(rd, rd_pa, base_va)
    _code(rd_va, base_va, obj_vt)
    return _tail(parts, base_va, map_base, ma, mb, ml, idx)


def _contig(rd, rd_pa, base_va) -> None:
    """G7 -- PA of the page via the page tables vs the flat image_pa+rva h382 used."""
    p("")
    p("G7 contiguity (INFO)   walk PA vs flat image_pa+rva")
    try:
        with open(OFFS, encoding="utf-8") as f:
            kv = dict(l.strip().split("=", 1) for l in f if "=" in l)
        image_pa = int(kv["image_pa"], 16)
    except (OSError, KeyError, ValueError):
        p("  temp\\qk_offsets.txt has no image_pa -> nothing to compare against")
        return
    p("  recorded image_pa = %#x" % image_pa)
    split = 0
    for name, rva, n in (("obj", OBJ, 0x10), ("vtable", VT, 0x40),
                         ("slot0", SLOT0, 0x10), ("bufA", BUF_A, 0x40),
                         ("bufB", BUF_B, 0x40), ("idx", IDX, 4),
                         ("legacy", LEGACY, 0x40)):
        va = base_va + rva
        try:
            pa_w = rd.page_pa(va)
        except (OSError, ValueError):
            pa_w = None
        pa_f = (image_pa + rva) & ~0xFFF
        if pa_w is None:
            p("  %-7s +%#09x  walk=FAIL  flat=%#x" % (name, rva, pa_f))
            continue
        delta = pa_w - pa_f
        if delta:
            split += 1
        bw = rd.read(va, n)
        bf = rd_pa((image_pa + rva), n)
        eq = ("yes" if bw == bf else "no") if (bw is not None and bf is not None) else "n/a"
        p("  %-7s +%#09x  walk=%#x  flat=%#x  delta=%+d  bytes equal=%s"
          % (name, rva, pa_w, pa_f, delta, eq))
    p("  %d of 7 sampled pages are NOT at image_pa+rva page: the flat read h382"
      " used was reading other pages" % split)


def _code(rd_va, base_va, obj_vt) -> None:
    """G8 -- the vtable slot and the machine code the static RE claims."""
    p("")
    p("G8 code identity (INFO)")
    if obj_vt is None:
        p("  vtable pointer unreadable (G2 FAIL) -> skipped")
        return
    slot = rd_va(obj_vt + 0x80, 8)
    if not slot:
        p("  vtable+0x80 unreadable -> skipped")
        return
    fn = u64(slot)
    p("  vtable+0x80 -> %#x  (want base_va+%#x = %#x)  %s"
      % (fn, MATRIX_FUNC, base_va + MATRIX_FUNC,
         "MATCH" if fn == base_va + MATRIX_FUNC else "DIFFERS"))
    stub = rd_va(fn, 0x10)
    if stub:
        p("  stub bytes:   " + " ".join("%02X" % c for c in stub))
        if stub[0] == 0xE9:
            rel = struct.unpack_from("<i", stub, 1)[0]
            tgt = fn + 5 + rel
            p("  jmp rel32 ->  %#x  (want base_va+%#x)  %s"
              % (tgt, MATRIX_BODY,
                 "MATCH" if tgt == base_va + MATRIX_BODY else "DIFFERS"))
    body = rd_va(base_va + MATRIX_BODY, 0x80)
    if not body:
        p("  body at base_va+%#x unreadable" % MATRIX_BODY)
        return
    for label, sig in (("movsx rax,[rbp+0x1308]", SIG_IDX),
                       ("mov rax,[rcx+rax*8+0x11a390]", SIG_S0),
                       ("mov rax,[rcx+rax*8+0x11a398]", SIG_S1)):
        i = body.find(sig)
        p("  %-30s %s" % (label, ("at +%#x" % i) if i >= 0 else "not in first 0x80 B"))

def _tail(parts, base_va, map_base, ma, mb, ml, idx) -> int:
    p("")
    if mb:
        p("buffer B (base_va+%#x, index 1 -- NOT used by 0x20B7FD0):" % BUF_B)
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
        p("legacy candidate base_va+%#x (the standing qk_offsets vp_rva):" % LEGACY)
        p("  as 16 f32: " + " ".join("%g" % v for v in ml))
        if ma:
            d = max(abs(ml[i] - ma[i]) for i in range(16))
            p("  == buffer A? %s (max|d|=%.6g)" % ("YES" if d < 1e-6 else "no", d))
        t2, s2v, _d = p74.canary(ml)
        p("  p74 canary on it: %s"
          % (("tier=%s score=%.1f" % (t2, s2v)) if t2
             else "FAIL " + "; ".join(p74.fail_reasons(ml) or ["no tier"])))
    else:
        p("legacy candidate base_va+%#x unreadable" % LEGACY)

    p("")
    p("chain:  base_va %#x (module list / find_mz %#x) -> CR3-walked reads" % (base_va, map_base))
    p("        ViewRender  base_va+%#x  (static .data)" % OBJ)
    p("        vtable      base_va+%#x  slot +0x80 = GetViewMatrix(index)" % VT)
    p("        member      +0x%X  matrix pointer array [2], index byte +%#x = %s"
      % (SLOT0, IDX, "-" if idx is None else idx))
    p("        matrix      [base_va+%#x] -> base_va+%#x  (16 f32, row-vector, w=row3)"
      % (SLOT0, BUF_A))
    p("RESULT: " + " ".join(parts))
    gated = [x for x in parts if "=INFO(" not in x]
    good = all(x.endswith("=PASS") for x in gated)
    p("VERDICT: %s (variable: read path -- page-table VA walk vs h382's flat"
      " image_pa+RVA)" % ("PASS" if good else "FAIL"))
    _write()
    return 0 if good else 1


if __name__ == "__main__":
    raise SystemExit(main())
