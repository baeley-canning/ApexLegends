r"""_mk20_unit.py -- prove the _mk20 verdict before it is allowed to judge a real read.

The claim under test is narrow and checkable: given a raw file that contains a real
view-projection matrix and a set of entity records, find the matrix; given a file that
contains only a decoy (an entity transform, a zero block), say FAIL instead of
inventing a winner.  Everything else in _mk20 (gio, retries, the image) is transport,
and transport is not what this file is about.

  python temp\_mk20_unit.py -> UNIT: n/n
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ext"))
sys.path.insert(0, HERE)

import _mk20 as k                                             # noqa: E402
import _vp2d as vp                                            # noqa: E402

T = os.path.join(HERE, "mk20_unit")
W, H = k.W, k.H
EYE = (1000.0, 2000.0, 300.0)
YAW, PITCH = 45.0, -5.0


def entities(eye, d_near=60.0):
    """A few in-frustum origins plus one far behind: the far one must not decide."""
    out = []
    for d in (d_near, 90.0, 140.0, 600.0, 2500.0):
        a = vp.CORNERS  # noqa: F841  (keep the import obviously used)
        out.append((eye[0] + d * 0.7071, eye[1] + d * 0.7071, eye[2] - 5.0))
    out.append((eye[0] - 2000.0, eye[1] - 2000.0, eye[2]))
    return out


def record(org, layout):
    """0xC0 bytes of a census record with the origin in one of the layouts."""
    f = [0.0] * 48
    if layout == "rows/col0":
        for i, v in enumerate(org):
            f[i * 4] = v
    elif layout == "rows/col3":
        for i, v in enumerate(org):
            f[i * 4 + 3] = v
    else:
        f[0:3] = list(org)
    for i in range(12, 48):
        f[i] = 0.0
    return struct.pack("<48f", *f)


def write_raw(path, mats, seeds):
    with open(path, "w", encoding="utf-8") as f:
        f.write("# _mk20 unit  pid=test image_pa=0x0 size=0x0 stamp=0x0 ranges=0\n")
        for rva, blob in mats:
            f.write("mat %#x %s\n" % (rva, blob.hex()))
        for pa, b in seeds:
            f.write("seed %#x %s\n" % (pa, b.hex()))


def run(name, mats, seeds, want_rc, want_rva=None, layout="rows/col0"):
    os.makedirs(T, exist_ok=True)
    raw = os.path.join(T, "raw_%s.txt" % name)
    k.OUT = os.path.join(T, "out_%s.txt" % name)
    k.RECTS = os.path.join(T, "rects_%s.txt" % name)
    open(k.OUT, "w").close()
    write_raw(raw, mats, seeds)
    rc = k.verify(raw)
    txt = open(k.OUT, encoding="utf-8").read()
    lines = [ln.strip() for ln in txt.splitlines()]
    ok = (rc == want_rc)
    if ok and want_rva is not None:
        ok = any(ln.startswith("RESULT:") and ("rva=%#x" % want_rva) in ln
                 for ln in lines)
        ok = ok and any(ln.startswith("VERDICT: PASS") for ln in lines)
    if ok and layout:
        ok = any(("layout=%s" % layout) in ln for ln in lines)
    print("   %-6s -> %s (rc=%d)" % (name, "OK" if ok else "BAD", rc))
    return ok


def main():
    m = vp.vp_from_yaw_pitch(YAW, PITCH, EYE, W, H)
    ents = entities(EYE)
    # the census's own layout (v[i], v[i+1], v[i+2]) - three consecutive floats
    seeds = [(0x160000000 + i * 0xC0, record(o, "contig"))
             for i, o in enumerate(ents)]
    blob = struct.pack("<16f", *m)

    ok = []
    # 1. the real VP next to a decoy: the VP must win, by rva
    aff = list(m)
    aff[3] = aff[7] = aff[11] = 0.0
    aff[15] = 1.0
    ok.append(run("vp", [(0x5000, struct.pack("<16f", *aff)), (0x9000, blob)],
                  seeds, 0, want_rva=0x9000, layout="contig"))

    # 2. only the decoy (an affine with no perspective row): FAIL, no winner
    ok.append(run("decoy", [(0x5000, struct.pack("<16f", *aff))], seeds, 1,
                  layout=None))

    # 3. a zero block is not a matrix
    ok.append(run("zeros", [(0x5000, bytes(0x70))], seeds, 1, layout=None))

    # 4. the records carry the origin strided instead of contiguous: contig is
    #    unusable there, so the scan must fall back to the strided layouts
    seeds3 = [(pa, record(o, "rows/col3")) for (pa, _), o
              in zip(seeds, ents)]
    ok.append(run("layout3", [(0x9000, blob)], seeds3, 0, want_rva=0x9000,
                  layout="rows/col3"))

    # 5. the matrix is stored transposed: still the same matrix, found via col
    tr = [m[(i % 4) * 4 + (i // 4)] for i in range(16)]
    ok.append(run("transposed", [(0x9000, struct.pack("<16f", *tr))], seeds, 0,
                  want_rva=0x9000, layout="contig"))

    print("UNIT: %d/%d" % (sum(1 for x in ok if x), len(ok)))
    if all(ok):
        print("VERDICT: PASS - the verdict finds a real VP and refuses decoys")
        return 0
    print("VERDICT: FAIL - see the case above")
    return 1


if __name__ == "__main__":
    sys.exit(main())
