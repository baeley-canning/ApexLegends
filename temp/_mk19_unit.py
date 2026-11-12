r"""_mk19_unit.py -- gate for the offline half of _mk19.

Builds a dump with a KNOWN camera and known entity origins, then asserts that
--solve recovers that exact offset, in both storage conventions, and that noise
alone yields a FAIL.  No gio, no game, no elevation: this is the part of the
pipeline a dump is supposed to make testable.
"""
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import _mk19 as mk                                          # noqa: E402
import _vp2d as vp                                          # noqa: E402

T = os.path.join(HERE, "dump_unit")
W, H = 1920, 1080
CAM = (5123.0, -2877.0, 210.5)


def build(path, mat, mat_off, size=0x100000, seed=5):
    """A dump-shaped buffer: bounded noise with `mat` written at `mat_off`."""
    import random
    random.seed(seed)
    a = [random.uniform(-50.0, 50.0) for _ in range(size // 4)]
    b = bytearray(struct.pack("<%df" % len(a), *a))
    if mat is not None:
        struct.pack_into("<16f", b, mat_off, *mat)
    with open(path, "wb") as f:
        f.write(b)
    return len(b)


def write_meta(meta_path, size, image_pa, data_rva):
    with open(meta_path, "w", encoding="utf-8") as f:
        f.write("time=unit\npid=0\n")
        f.write("image_pa=%#x\nimage_size=%#x\nstamp=%#x\n"
                % (image_pa, 0x1000, 0x0))
        f.write("data_rva=%#x\ndata_size=%#x\n" % (data_rva, size))
        f.write("band_pa=%#x\nband_size=%#x\n" % (0, 0))
        f.write("ranges=unit\n")
        f.write("data_refused=0\nband_refused=0\n")


def write_seeds(seed_path, orgs, transform=False):
    import math as _m
    with open(seed_path, "w", encoding="utf-8") as f:
        f.write("# pa 24 floats raw=hex\n")
        for i, o in enumerate(orgs):
            if transform:
                # a real record: rows of a rotation at 0x10 stride, the
                # translation in the 4th column of each row (f3,f7,f11)
                a = _m.radians(i * 47.0)
                fl = [_m.cos(a), _m.sin(a), 0.0, o[0],
                      -_m.sin(a), _m.cos(a), 0.0, o[1],
                      0.0, 0.0, 1.0, o[2]]
                fl += [0.0] * 12
            else:
                fl = [o[0], 999.0, 998.0, 0.0, o[1], 0.0, 0.0, 1.0,
                      o[2], 7.0, 7.0, 0.0]
                fl += [0.0] * 12
            f.write("%#x %s raw=%s\n"
                    % (0x140000000 + i * 0xC0,
                       " ".join("%.6g" % v for v in fl), "00" * 16))


def patch(D, M, S, R, O):
    mk.DATA, mk.META, mk.SEEDS, mk.RECTS, mk.OUT = D, M, S, R, O


def run_case(name, mat, mat_off, expect_pa, orgs, want, transform=False):
    os.makedirs(T, exist_ok=True)
    D = os.path.join(T, "data_%s.bin" % name)
    M = os.path.join(T, "meta_%s.txt" % name)
    S = os.path.join(T, "seeds_%s.txt" % name)
    R = os.path.join(T, "rects_%s.txt" % name)
    O = os.path.join(T, "out_%s.txt" % name)
    size = build(D, mat, mat_off)
    write_meta(M, size, 0x100000000, 0x1000)
    write_seeds(S, orgs, transform=transform)
    patch(D, M, S, R, O)
    rc = mk.solve()
    body = open(O, encoding="utf-8").read()
    result = [ln for ln in body.splitlines() if ln.startswith("RESULT:")]
    verdict = [ln for ln in body.splitlines() if ln.startswith("VERDICT:")]
    print("--- %s ---" % name)
    for ln in body.splitlines():
        if ln.startswith(("  ", "RESULT:", "VERDICT:")):
            print("   " + ln)
    ok = bool(result and verdict)
    if expect_pa is not None:
        ok = ok and ("pa=%#x" % expect_pa) in body and rc == 0
        ok = ok and " on=" in body and "VERDICT: PASS" in body
    else:
        ok = ok and verdict[0].startswith("VERDICT: FAIL") and rc == 1
    print("   %s -> %s (rc=%d)" % (name, "OK" if ok else "BAD", rc))
    return ok


def main():
    m = vp.vp_from_yaw_pitch(37.0, -5.0, CAM, W, H)
    orgs = []
    for i in range(12):
        a = math.radians(i * 30.0)
        orgs.append((CAM[0] + 45.0 * math.cos(a), CAM[1] + 45.0 * math.sin(a),
                     205.0))
    off = 0x40000
    ok = []

    ok.append(run_case("row", m, off, 0x100000000 + 0x1000 + off, orgs, True))

    mt = mk._transpose(m)
    ok.append(run_case("col", mt, off, 0x100000000 + 0x1000 + off, orgs, True))

    ok.append(run_case("noise", None, off, None, orgs, False))

    # a matrix whose camera is nowhere near any entity must not survive
    far = vp.vp_from_yaw_pitch(200.0, 3.0, (-9000.0, 9000.0, 900.0), W, H)
    ok.append(run_case("far", far, off, None, orgs, False))

    # real records are 3x4 transforms; the fitter must recover their
    # translation column instead of reading a rotation column as a position
    ok.append(run_case("fit", m, off, 0x100000000 + 0x1000 + off, orgs, True,
                       transform=True))

    print("UNIT: %d/%d" % (sum(ok), len(ok)))
    print("VERDICT: %s" % ("PASS - offline solver recovers a known VP from a dump"
                           if all(ok) else "FAIL - see the case above"))
    return 0 if all(ok) else 1


if __name__ == "__main__":
    sys.exit(main())
