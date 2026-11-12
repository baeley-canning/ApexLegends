r"""_vp2d.py -- world -> screen rect, the last mile between "I can read a field"
and "there is a box on the screen".

Pure math, no transport, no repo imports, so it is testable without the game and
without elevation:  python temp\_vp2d.py  runs the self-check.

Two ways in:

  project(m, ...)      with a live 4x4.  Both matrix conventions are tried
                       explicitly and BOTH are reported; whichever convention the
                       build turned out to use is then known instead of assumed.
                       (qk_phys.project also tries both, but returns the first
                       candidate with positive w, i.e. it silently prefers "col".)
  vp_from_yaw_pitch()  degenerate path: build the matrix from yaw/pitch/fov.  Lets
                       the rect pipeline be proven before the ViewMatrix RVA is
                       verified in this build.

Convention here: row-vector, p' = p M, with
  row0 = right / (tan * aspect)     row1 = down / tan     row3 = forward
so w' is view depth and rows 0-1 already carry the perspective divide.  +Z is up
(Apex), yaw counter-clockwise from +X.

Nothing in this file claims an offset.  Callers pass them.
"""
import math

CORNERS = tuple((i, j, k) for i in (0, 1) for j in (0, 1) for k in (0, 1))


def layout_of(m):
    """Where the perspective/depth quantity lives, or None if not row-major.

      "w"  row 3 carries forward, w = depth (perspective row, what vp_from_yaw_pitch builds)
      "z"  row 3 is 0001, depth is z' on row 2 (classic Source ViewMatrix)

    Getting this wrong is silent: a classic matrix has w == 1 for every point, so
    dividing by w projects at the wrong scale and still returns plausible numbers.
    """
    if any(x != x for x in m):
        return None
    third = any(abs(m[12 + i]) > 1e-6 for i in range(3))
    if abs(m[15] - 1.0) > 1e-3:
        return "w" if third else None
    return "w" if third else "z"


def project_tag(m, x, y, z, w, h, tag="row", wsrc="w"):
    """(sx, sy, depth) for one convention + one depth source, None if behind."""
    if tag == "row":                                      # p' = p M   (Source engine)
        px = m[0] * x + m[1] * y + m[2] * z + m[3]
        py = m[4] * x + m[5] * y + m[6] * z + m[7]
        pw = m[12] * x + m[13] * y + m[14] * z + m[15]
        pz = m[8] * x + m[9] * y + m[10] * z + m[11]
    else:                                                 # p' = M p   (GL/D3D style)
        px = m[0] * x + m[4] * y + m[8] * z + m[12]
        py = m[1] * x + m[5] * y + m[9] * z + m[13]
        pw = m[3] * x + m[7] * y + m[11] * z + m[15]
        pz = m[2] * x + m[6] * y + m[10] * z + m[14]
    d = pz if wsrc == "z" else pw
    if d != d or d <= 1e-6:
        return None
    return (px / d * 0.5 + 0.5) * w, (0.5 - py / d * 0.5) * h, d


def project(m, x, y, z, w, h):
    """(sx, sy, depth, tag) - both conventions, first one in front.  For scoring
    an unknown matrix; NOT for rects (the tags then differ between corners)."""
    for tag in ("row", "col"):
        p = project_tag(m, x, y, z, w, h, tag)
        if p:
            return p[0], p[1], p[2], tag
    return None


def rect_for(m, org, mins, maxs, w, h, tag="row", min_corners=4, wsrc=None):
    """Screen rect for an entity AABB, or None.

    `org` is the entity origin, `mins`/`maxs` its collision bounds RELATIVE to
    that origin (m_vecMins/m_vecMaxs semantics).  One convention only - mixing
    them per-corner would stretch the rect.  Corners behind the near plane are
    dropped, so a box straddling it still yields the visible part.  A rect needs
    `min_corners` surviving corners and must overlap the screen.
    """
    if wsrc is None:
        wsrc = layout_of(m) or "w"
    ox, oy, oz = org
    pts = []
    for i, j, k in CORNERS:
        x = ox + (maxs[0] if i else mins[0])
        y = oy + (maxs[1] if j else mins[1])
        z = oz + (maxs[2] if k else mins[2])
        p = project_tag(m, x, y, z, w, h, tag, wsrc)
        if not p:
            continue
        pts.append(p)
    if len(pts) < min_corners:
        return None
    x0 = min(p[0] for p in pts)
    x1 = max(p[0] for p in pts)
    y0 = min(p[1] for p in pts)
    y1 = max(p[1] for p in pts)
    if x1 < 0 or x0 > w or y1 < 0 or y0 > h:
        return None
    return {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "tag": tag,
            "depth": sum(p[2] for p in pts) / len(pts), "corners": len(pts)}



def vp_from_yaw_pitch(yaw_deg, pitch_deg, cam, w, h, fov_deg=70.0):
    """Row-major 4x4 in the convention above, from yaw/pitch/fov (degenerate path)."""
    y = math.radians(yaw_deg % 360.0)
    p = math.radians(max(-89.0, min(89.0, pitch_deg)))
    cy, sy = math.cos(y), math.sin(y)
    cp, sp = math.cos(p), math.sin(p)
    fwd = (cp * cy, cp * sy, sp)
    rgt = (sy, -cy, 0.0)
    dwn = (-sp * cy, -sp * sy, cp)
    t = math.tan(math.radians(fov_deg) * 0.5)
    a = float(w) / float(h)
    cx, cyy, cz = cam
    dot = lambda u, v: u[0] * v[0] + u[1] * v[1] + u[2] * v[2]      # noqa: E731
    m = [0.0] * 16
    for i in range(3):
        m[0 + i] = rgt[i] / (t * a)
        m[4 + i] = dwn[i] / t
        m[8 + i] = fwd[i]
        m[12 + i] = fwd[i]
    m[3] = -dot(rgt, cam) / (t * a)
    m[7] = -dot(dwn, cam) / t
    m[11] = -dot(fwd, cam)
    m[15] = -dot(fwd, cam)
    return m


def _selfcheck():
    W, H = 1920, 1080
    eye = [1000.0, 2000.0, 3000.0]
    m = vp_from_yaw_pitch(0.0, 0.0, eye, W, H)
    ax, ay, az = eye

    p = project(m, ax + 1000.0, ay, az, W, H)
    assert p and p[3] == "row", p
    assert abs(p[0] - 960) < 1 and abs(p[1] - 540) < 1, p          # dead ahead = centre

    p = project(m, ax + 500.0, ay - 100.0, az, W, H)
    assert p and p[0] > 960, p                                      # +x is right (-Y at yaw 0)

    p = project(m, ax + 500.0, ay, az + 100.0, W, H)
    assert p and p[1] < 540, p                                      # up is up

    assert project(m, ax - 100.0, ay, az, W, H) is None             # behind -> None

    r = rect_for(m, (ax + 1000.0, ay, az), (-20, -20, 0), (20, 20, 72), W, H)
    assert r and r["tag"] == "row" and r["y1"] > r["y0"], r
    assert r["x1"] - r["x0"] > 0 and 0 < r["y0"] < r["y1"] < H, r
    assert r["corners"] == 8, r                                     # all 8 in front

    # half the box behind the near plane: still a rect, fewer corners
    r2 = rect_for(m, (ax + 5.0, ay, az), (-20, -20, 0), (20, 20, 72), W, H)
    assert r2 and r2["corners"] < 8, r2

    # far off to the side: rejected
    assert rect_for(m, (ax + 1000.0, ay - 100000.0, az), (-20, -20, 0), (20, 20, 72),
                    W, H) is None

    # camera recovered from the matrix == the camera that built it
    mc = vp_from_yaw_pitch(45.0, 20.0, eye, W, H)
    got = cam_from_rows(mc)
    assert got and math.dist(got, eye) < 1e-6, got

    # verify(): an entity sitting on the camera must anchor
    vrows = [{"org": eye, "rect": rect_for(mc, eye, (-1, -1, -1), (1, 1, 1), W, H)},
             {"org": (ax + 1000.0, ay, az), "rect": r}]
    vs = verify(vrows, mc, "row")
    assert vs["anchor"] is not None and vs["anchor"] < 1.0 and vs["local"] == 1, vs

    # classic Source layout: same camera, depth on row 2, row 3 = 0001
    cls = list(mc)
    cls[12] = cls[13] = cls[14] = 0.0
    cls[15] = 1.0
    assert layout_of(cls) == "z" and layout_of(mc) == "w"
    assert math.dist(cam_from_rows(cls), eye) < 1e-6
    for org, mn, mx in (((ax + 800.0, ay, az), (-20, -20, 0), (20, 20, 72)),
                        ((ax + 40.0, ay + 60.0, az + 30.0), (-5, -5, 0), (5, 5, 30))):
        a = rect_for(mc, org, mn, mx, W, H, wsrc="w")
        b = rect_for(cls, org, mn, mx, W, H, wsrc="z")
        assert (a is None) == (b is None), (a, b)
        if a:
            for kk in ("x0", "y0", "x1", "y1"):
                assert abs(a[kk] - b[kk]) < 1e-6, (kk, a, b)
    # no row-major reading at all
    assert cam_from_rows([0.0] * 16) is None and layout_of([float("nan")] * 16) is None

    # the anchor must DISCRIMINATE: a camera 500u off its entities reads as far
    off = vp_from_yaw_pitch(45.0, 20.0, (ax + 500.0, ay, az), W, H)
    vo = verify(vrows, off, "row")
    assert vo["anchor"] is not None and vo["anchor"] > 400.0, vo
    # and it must work on the classic layout too, not just the perspective one
    vc = verify(vrows, cls, "row")
    assert vc["anchor"] is not None and vc["anchor"] < 1.0, vc

    md = vp_from_yaw_pitch(0.0, 30.0, eye, W, H)
    up = project(m, ax + 500.0, ay, az + 300.0, W, H)
    dn = project(md, ax + 500.0, ay, az + 300.0, W, H)
    assert up and dn and dn[1] > up[1], (up, dn)

    print("selfcheck OK  (centre/right/up/behind/rect/clip/pitch/layout/verify)")


def cam_from_rows(m):
    """World camera position implied by a row-major world->view matrix.

    v = R*p + t, so v = 0 at p = cam gives cam = -R^-1 t.  Rows 0..1 may be scaled
    by the perspective terms, so each row is normalised and the matching t
    component unscaled with it first; the result is then exact for both layouts.
    Returns None for anything that is not row-major.

    This is the cheap, pixel-free way to ask "is this really the view matrix?": a
    late-bound entity array must contain the local player, and the local player's
    m_localOrigin sits on the camera to within a few units.  If it does, both the
    matrix and the origin offset are right at once.
    """
    wsrc = layout_of(m)
    if not wsrc:
        return None
    fwd = m[12:15] if wsrc == "w" else m[8:11]
    rows = [(m[0], m[1], m[2]), (m[4], m[5], m[6]), tuple(fwd)]
    t = (m[3], m[7], m[11])
    unit, ts = [], []
    for i, row in enumerate(rows):
        n = math.sqrt(row[0] ** 2 + row[1] ** 2 + row[2] ** 2)
        if n < 1e-9:
            return None
        unit.append((row[0] / n, row[1] / n, row[2] / n))
        ts.append(t[i] / n)
    return tuple(-(ts[0] * unit[0][i] + ts[1] * unit[1][i] + ts[2] * unit[2][i])
                 for i in range(3))


def verify(rows, mat, tag, near=128.0):
    """Source-free plausibility of a projected entity set.  Returns a dict.

    `anchor` is the distance from the derived camera to the nearest entity origin
    (the local player should give a small number) and `aspect` counts rects whose
    width/height is human-ish (0.1..1.2).  Neither needs a screenshot.
    """
    st = {"n": len(rows), "on": 0, "aspect": 0, "anchor": None, "anchor_idx": -1,
          "local": 0}
    cam = cam_from_rows(mat) if tag == "row" else None
    best = None
    for r in rows:
        if cam:
            d = math.dist(cam, r["org"])
            if best is None or d < best:
                best = d
        rr = r["rect"]
        if not rr:
            continue
        st["on"] += 1
        w = rr["x1"] - rr["x0"]
        h = rr["y1"] - rr["y0"]
        if h > 1.0 and 0.1 <= w / h <= 1.2:
            st["aspect"] += 1
    if best is not None:
        st["anchor"] = best
        for r in rows:
            if math.dist(cam, r["org"]) <= near:
                st["local"] += 1
    return st


def _fuzz(n=3000, seed=17):
    """Invariants under random cameras/boxes.  Cheap, and it would have caught
    the exhausted-generator AND the mixed-convention bug."""
    import random
    rnd = random.Random(seed)
    W, H = 2560, 1440
    hits = 0
    for _ in range(n):
        eye = [rnd.uniform(-20000, 20000) for _ in range(3)]
        yaw = rnd.uniform(0, 360)
        pitch = rnd.uniform(-60, 60)
        m = vp_from_yaw_pitch(yaw, pitch, eye, W, H)
        # aim INSIDE the frustum (that is the invariant under test), then let a
        # few go to the edge: +-40 deg of a 51 deg half-FOV, +-25 of 35 vertical.
        d = rnd.uniform(200, 15000)
        yaw_b = math.radians(yaw + rnd.uniform(-40, 40))
        el = math.radians(pitch + rnd.uniform(-25, 25))
        org = (eye[0] + d * math.cos(el) * math.cos(yaw_b),
               eye[1] + d * math.cos(el) * math.sin(yaw_b),
               eye[2] + d * math.sin(el))
        mins = (-rnd.uniform(5, 40), -rnd.uniform(5, 40), -rnd.uniform(0, 30))
        maxs = (rnd.uniform(5, 40), rnd.uniform(5, 40), rnd.uniform(30, 120))
        r = rect_for(m, org, mins, maxs, W, H)
        if not r:
            continue
        hits += 1
        assert r["x1"] >= r["x0"] and r["y1"] >= r["y0"], r
        assert r["x1"] > 0 and r["x0"] < W and r["y1"] > 0 and r["y0"] < H, r
        assert r["depth"] > 0 and 1 <= r["corners"] <= 8, r
        assert all(math.isfinite(v) for v in
                   (r["x0"], r["y0"], r["x1"], r["y1"], r["depth"])), r
    assert hits > n * 0.9, hits                       # nearly all must land

    # distance shrinks a box
    eye = [0.0, 0.0, 0.0]
    m = vp_from_yaw_pitch(0, 0, eye, W, H)
    near = rect_for(m, (500.0, 0, 0), (-20, -20, 0), (20, 20, 72), W, H)
    far = rect_for(m, (1000.0, 0, 0), (-20, -20, 0), (20, 20, 72), W, H)
    assert near and far and (near["y1"] - near["y0"]) > (far["y1"] - far["y0"])

    # NaN in the matrix must not raise
    bad = [float("nan")] * 16
    rect_for(bad, (1.0, 1.0, 1.0), (-1, -1, 0), (1, 1, 1), W, H)
    print("fuzz OK  (%d boxes landed, %d tried)" % (hits, n))


if __name__ == "__main__":
    _selfcheck()
    _fuzz()

