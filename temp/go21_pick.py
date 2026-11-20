"""go21_pick.py -- passive VP-matrix election from qk_image's 8 candidates (go21).

Camera stood still during --watch, so the mover-check cached nothing. Motion-free
discriminators instead (all read-only):
  * projection-shaped:  sparse, aspect ratio hints 16:9 in the scale diagonal
  * view-shaped:        orthonormal 3x3 rotation + translation of realistic magnitude
  * twin clusters:      renderer keeps same-frame / prev-frame copies in tight groups
Writes nothing unless --pick=<idx> is passed: then temp\\qk_offsets.txt is authored
(image_pa + vp_rva) for the producer to consume (the file IS the contract).
"""
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "ext"))

import gio                                        # noqa: E402
import dumplive as dl                             # noqa: E402

IMAGE_PA = 0x048C6BD000                           # from today's PASS sweep
CANDS = (0x0DE43604, 0x0DE43270, 0x0DE431E0, 0x0DE43080,
         0x0DDF5A34, 0x0DDB5C04, 0x0DDB5844, 0x0DDB5390)


def ortho_err(m):
    """Rotation-block orthonormality residual, column-major 4x4."""
    cols = [m[0:3], m[4:7], m[8:11]]
    errs = []
    for i, c in enumerate(cols):
        errs.append(abs(math.sqrt(sum(v * v for v in c)) - 1.0))
        for j, d in enumerate(cols):
            if j > i:
                errs.append(abs(sum(a * b for a, b in zip(c, d))))
    return max(errs)


def classify(m):
    fin = all(x == x and abs(x) < 1e12 for x in m)
    diag = abs(m[0]), abs(m[5])
    proj_like = (fin and abs(m[11]) >= 0.99 and m[3] == 0.0 and m[7] == 0.0
                 and abs(diag[1] - diag[0] / (1920.0 / 1080.0)) < 0.05 * diag[0])
    oe = ortho_err(m) if fin else 9e9
    tn = math.sqrt(m[12] ** 2 + m[13] ** 2 + m[14] ** 2)
    view_like = fin and oe < 1e-3 and (100.0 < tn < 20000.0)
    return fin, proj_like, view_like, oe, tn


def main():
    if not dl.elevation() and "--no-elevate" not in sys.argv:
        argv = [os.path.abspath(a) for a in sys.argv]
        cmd = " ".join('"%s"' % a if " " in a else a for a in argv) + " --no-elevate"
        print(dl.run_elevated(cmd))
        return 0
    pick = None
    for a in sys.argv:
        if a.startswith("--pick="):
            pick = int(a.split("=")[1], 0)
    g = gio.Gio(chunk=0x10000)
    try:
        print("candidate           fin proj view orthoErr |trans|  floats")
        for idx, rva in enumerate(CANDS):
            try:
                m = struct.unpack("<16f", dl.retry_phys(g, IMAGE_PA + rva, 64, tries=2))
            except OSError as e:
                print("[%d] %#010x read fault: %s" % (idx, rva, e))
                continue
            fin, pj, vw, oe, tn = classify(m)
            fs = " ".join("%10.4g" % x for x in m)
            print("[%d] %#010x %d %5s %5s %8.1e %8.1f  %s"
                  % (idx, rva, fin, pj, vw, oe, tn, fs))
        if pick is None:
            print("RESULT: election pending - inspect above, then rerun --pick=<idx>")
            return 0
        sel = CANDS[pick]
        with open(os.path.join(HERE, "temp", "qk_offsets.txt"), "w") as f:
            f.write("image_pa=0x%X\nvp_rva=0x%X\n" % (IMAGE_PA, sel))
        print("RESULT: cached temp\\qk_offsets.txt image_pa=%#x vp_rva=%#x (pick %d)"
              % (IMAGE_PA, sel, pick))
        print("VERDICT: PICKED - producer may fire")
        return 0
    finally:
        g.close()


if __name__ == "__main__":
    main()
