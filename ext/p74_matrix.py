r"""p74_matrix.py -- offline 16-float view-matrix canary scan (Lane R, Phase 1 T2).

Scans the p73 offline corpus for 16-float blocks passing the view-matrix canary:

  HARD gates: all 16 finite f32; |m[15]| > 1e-6; |m[0]| and |m[5]| each in
      [0.3, 3.0] (FOV-plausible); perspective shape: |m[11]| > 1e-6 or
      |m[14]| > 1e-6.
      Magnitude sanity (added after the v1 run, see p74_matrix_v1_loose.out:
      FLT_MAX sentinel tables otherwise dominate .rdata/.data, 448 cand/MB):
      forward row (m8,m9,m10) length in the same tier band as right/up rows,
      |m[11]| < 100 (forward-z is unit-ish or -1, never FLT_MAX), and each
      |m[12]|,|m[13]|,|m[14]| < 1e6 (world translation is bounded).
      Orthogonality (added after the v2 run, see p74_matrix_v2_noortho.out:
      color/parameter float ramps otherwise dominate, 409 cand/MB): the three
      row 3-vectors right/up/forward must be mutually orthogonal within 0.05
      (true for a rotation block and for its FOV-scaled VP form; a data ramp
      of small fractions is not orthogonal).
  TIER A ("near-unit rows" -- pure view matrix, rotation + translation):
      right row (m0,m1,m2) and up row (m4,m5,m6) lengths each in [0.7, 1.4].
  TIER B (view-projection shape): row lengths each in [0.3, 3.0] (rows carry
      the FOV/aspect scale instead; 16:9 puts xScale near 0.56, below tier A).
  Candidates are ranked by a soft score: row lengths near 1, m[3]/m[7] == 0,
      |m[15]-1| small (pure view), |m[15]| large (VP, -tz), right/up orthogonal,
      translation-ish last row.

ANTI-EXAMPLE, treated explicitly: RVA 0x022EE01 (today's ApexOffsets::
VIEW_MATRIX) is VTP_GetEngineTraceClient CODE in .text.  The 16 floats read
there must FAIL the canary -- that failure is docs-gap-1, the reason ESP stays
empty until the matrix RVA is re-RE'd.

Corpora (from _ritual\p73_assets.out, usable=4; all offline, read-only):
  1. C:\Program Files\EA Games\Apex\r5apex_dx12.exe  (.data + .rdata raw
     of the exact 04-05/11 live-probe build)
  2. temp\dm11_cache.pkl  (27/10-build .data-tail reconstruction; contiguous
     VA runs >= 64 B, None bytes filled 0x00)
  3. temp\p60_snap_before.txt + temp\p60_snap_after.txt (live entity-cluster
     dwords; p60_snap.py omits zero dwords, they are filled 0x00000000 here)

The RUNTIME view matrix is in none of these (no live .data dump survives, see
p73 E1) -- this scan validates the canary, measures its false-positive rate on
real build bytes, and ranks structural candidates.  The live-matrix hunt is the
p75 rotate-90 differential over a live .data dump (lead approval required).
--region=path:0xVA scans a raw region dump for that protocol.

Self-test: a synthetic buffer (pure-view matrix at a known offset, a VP-shaped
matrix at another, code-like ASCII bytes, zeros) must yield exactly the two
planted candidates and nothing else BEFORE any real corpus is touched.

Usage:
  python ext\p74_matrix.py                (selftest + all four corpora)
  python ext\p74_matrix.py --selftest-only
  python ext\p74_matrix.py --region=temp\x.bin:0x14334C000
Output: _ritual\p74_matrix.out (this probe's own file, R5).
"""
import array
import math
import os
import pickle
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

EXE = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
PICKLE = os.path.join(ROOT, "temp", "dm11_cache.pkl")
SNAPS = [os.path.join(ROOT, "temp", "p60_snap_before.txt"),
         os.path.join(ROOT, "temp", "p60_snap_after.txt")]
OUT_DEF = os.path.join(ROOT, "_ritual", "p74_matrix.out")

ANTI_RVA = 0x022EE01          # ApexOffsets::VIEW_MATRIX today (VTP code, .text)
FOV_LO, FOV_HI = 0.3, 3.0     # |m[0]|, |m[5]| band
NEAR_LO, NEAR_HI = 0.7, 1.4   # tier A row-length band (near unit)
VP_LO, VP_HI = 0.3, 3.0       # tier B row-length band (FOV-scaled)
EPS = 1e-6
MINRUN = 64                   # min contiguous bytes for dm11 runs
REPORT_CAP = 40               # candidates printed per corpus


class Out(object):
    def __init__(self, path):
        self.h = open(path, "w", encoding="ascii")

    def __call__(self, s=""):
        print(s)
        self.h.write(s + "\n")
        self.h.flush()

    def close(self):
        self.h.close()


def canary(m):
    """m: 16 floats. -> (tier, score, di); tier None when rejected."""
    for v in m:
        if v != v or v in (float("inf"), float("-inf")):
            return None, 0.0, None            # non-finite (NaN != NaN)
    if abs(m[15]) <= EPS:
        return None, 0.0, None
    if not (FOV_LO <= abs(m[0]) <= FOV_HI):
        return None, 0.0, None
    if not (FOV_LO <= abs(m[5]) <= FOV_HI):
        return None, 0.0, None
    if abs(m[11]) <= EPS and abs(m[14]) <= EPS:
        return None, 0.0, None
    rl = math.sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2])
    ul = math.sqrt(m[4] * m[4] + m[5] * m[5] + m[6] * m[6])
    fl = math.sqrt(m[8] * m[8] + m[9] * m[9] + m[10] * m[10])
    dot = m[0] * m[4] + m[1] * m[5] + m[2] * m[6]
    if abs(m[11]) >= 100.0:
        return None, 0.0, None                  # FLT_MAX sentinels / junk m11
    if abs(m[12]) >= 1e6 or abs(m[13]) >= 1e6 or abs(m[14]) >= 1e6:
        return None, 0.0, None                  # world translation bounded
    if NEAR_LO <= rl <= NEAR_HI and NEAR_LO <= ul <= NEAR_HI:
        tier = "A"
    elif VP_LO <= rl <= VP_HI and VP_LO <= ul <= VP_HI:
        tier = "B"
    else:
        return None, 0.0, None
    if not ((NEAR_LO <= fl <= NEAR_HI) if tier == "A" else (VP_LO <= fl <= VP_HI)):
        return None, 0.0, None                  # forward row: same band
    drf = m[0] * m[8] + m[1] * m[9] + m[2] * m[10]
    duf = m[4] * m[8] + m[5] * m[9] + m[6] * m[10]
    if abs(dot) >= 0.05 or abs(drf) >= 0.05 or abs(duf) >= 0.05:
        return None, 0.0, None                  # rows must be orthogonal
    score = 3.0 * max(0.0, 1.0 - abs(rl - 1.0)) + 3.0 * max(0.0, 1.0 - abs(ul - 1.0))
    if m[3] == 0.0:
        score += 2.0
    if m[7] == 0.0:
        score += 2.0
    if abs(m[15] - 1.0) < 1e-3:
        score += 2.0                          # pure-view marker (m15 == 1)
    if abs(m[15]) > 1.0:
        score += 1.0                          # VP marker (m15 == -tz, large)
    if abs(dot) < 0.02:
        score += 2.0
    if abs(m[12]) > 1.0 or abs(m[13]) > 1.0 or abs(m[14]) > 1.0:
        score += 1.0                          # translation-ish
    return tier, score, {"rl": rl, "ul": ul, "fl": fl, "dot": dot}


def fail_reasons(m):
    """Which hard gates fail (for the anti-example report)."""
    why = []
    for i, v in enumerate(m):
        if v != v or v in (float("inf"), float("-inf")):
            why.append("m[%d] non-finite" % i)
    if abs(m[15]) <= EPS:
        why.append("m[15]==0")
    if not (FOV_LO <= abs(m[0]) <= FOV_HI):
        why.append("|m[0]|=%.4g outside [0.3,3.0]" % abs(m[0]))
    if not (FOV_LO <= abs(m[5]) <= FOV_HI):
        why.append("|m[5]|=%.4g outside [0.3,3.0]" % abs(m[5]))
    if abs(m[11]) <= EPS and abs(m[14]) <= EPS:
        why.append("no perspective shape (m[11]==m[14]==0)")
    return why



def scan_buffer(buf, label, base, out):
    """Scan buf (bytes) at 4-byte stride; base = address of buf[0].
    Returns (nA, nB, top) where top is the ranked candidate list."""
    if len(buf) < 64:
        return 0, 0, []
    usable = len(buf) - (len(buf) % 4)
    a = array.array("f")
    a.frombytes(buf[:usable])
    n = len(a) - 15
    hits = []
    for i in range(n):
        m15 = a[i + 15]
        if m15 == 0.0 or m15 != m15:            # zero or NaN
            continue
        m0 = a[i]
        if m0 != m0:
            continue
        a0 = -m0 if m0 < 0.0 else m0
        if a0 < FOV_LO or a0 > FOV_HI:
            continue
        m5 = a[i + 5]
        if m5 != m5:
            continue
        a5 = -m5 if m5 < 0.0 else m5
        if a5 < FOV_LO or a5 > FOV_HI:
            continue
        m = a[i:i + 16]
        tier, score, di = canary(m)
        if tier is None:
            continue
        hits.append((score, base + 4 * i, tier, list(m), di))
    nA = sum(1 for h in hits if h[2] == "A")
    nB = len(hits) - nA
    hits.sort(key=lambda h: (-h[0], h[1]))
    out("  scanned %s bytes at %#x: tierA=%d tierB=%d" % (label, base, nA, nB))
    for score, va, tier, m, di in hits[:REPORT_CAP]:
        out("  CAND tier=%s score=%.1f addr=%#x rl=%.4f ul=%.4f fl=%.4f dot=%.4f"
            % (tier, score, va, di["rl"], di["ul"], di["fl"], di["dot"]))
        out("       floats %s" % " ".join("%g" % v for v in m))
    if len(hits) > REPORT_CAP:
        out("  ... %d more below report cap" % (len(hits) - REPORT_CAP))
    return nA, nB, hits


def parse_pe(path):
    data = open(path, "rb").read()
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    if data[e_lfanew:e_lfanew + 4] != b"PE\x00\x00":
        raise ValueError("bad PE signature")
    nsec = struct.unpack_from("<H", data, e_lfanew + 6)[0]
    opt_size = struct.unpack_from("<H", data, e_lfanew + 20)[0]
    opt = e_lfanew + 24
    if struct.unpack_from("<H", data, opt)[0] != 0x20B:
        raise ValueError("not PE32+")
    imagebase = struct.unpack_from("<Q", data, opt + 24)[0]
    sizeofimage = struct.unpack_from("<I", data, opt + 56)[0]
    secs = []
    st = opt + opt_size
    for i in range(nsec):
        off = st + i * 40
        name = data[off:off + 8].rstrip(b"\x00").decode("latin1")
        vsz, va, rsz, rp = struct.unpack_from("<IIII", data, off + 8)
        secs.append((name, va, vsz, rsz, rp))
    return data, imagebase, sizeofimage, secs


def rva_to_off(secs, rva):
    for name, va, vsz, rsz, rp in secs:
        if va <= rva < va + max(vsz, rsz):
            d = rva - va
            if d < rsz:
                return rp + d, name
            return None, name + " (virtual-only tail)"
    return None, None


def load_pickle_runs(path):
    """dm11_cache.pkl img dict -> [(start_va, bytes)] for runs >= MINRUN."""
    with open(path, "rb") as f:
        d = pickle.load(f)
    img = d["img"]
    ks = sorted(img.keys())
    runs = []
    start = prev = ks[0]
    for k in ks[1:]:
        if k == prev + 1:
            prev = k
            continue
        if prev - start + 1 >= MINRUN:
            runs.append((start, prev))
        start = prev = k
    if prev - start + 1 >= MINRUN:
        runs.append((start, prev))
    out = []
    for lo, hi in runs:
        out.append((lo, bytes(img.get(k) or 0 for k in range(lo, hi + 1))))
    return out, d.get("base", 0)


def load_snap_pages(path):
    """p60_snap file -> [(page_pa, 4096 bytes)] (omitted dwords = 0)."""
    pages = {}
    with open(path, "r", encoding="ascii", errors="replace") as f:
        for line in f:
            if not line.startswith("0x"):
                continue
            parts = line.split()
            if len(parts) < 2:
                continue
            try:
                addr = int(parts[0], 16)
                val = int(parts[1], 16)
            except ValueError:
                continue
            pages.setdefault(addr & ~0xFFF, {})[addr & 0xFFF] = val
    out = []
    for pg in sorted(pages):
        d = pages[pg]
        buf = bytearray(4096)
        for off, val in d.items():
            struct.pack_into("<I", buf, off, val & 0xFFFFFFFF)
        out.append((pg, bytes(buf)))
    return out


def selftest(out):
    """Synthetic buffer: pure-view matrix at 0x540, VP-shaped at 0xA40,
    code-like ASCII at 0x1500+, zeros elsewhere.  Exactly 2 candidates must
    appear, tier A at 0x540 and tier B at 0xA40, before any real corpus."""
    buf = bytearray(8192)
    # pure view matrix, yaw 30 deg, z-up, translation (all rows orthonormal)
    view = [0.8660254, 0.5, 0.0, 0.0,
            -0.5, 0.8660254, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            120.5, -33.25, 88.75, 1.0]
    struct.pack_into("<16f", buf, 0x540, *view)
    # view-projection shape: rows carry FOV/aspect scale, m15 = -tz
    vp = [0.4 * 0.8660254, 0.4 * 0.5, 0.0, 0.0,
          -0.9 * 0.5, 0.9 * 0.8660254, 0.0, 0.0,
          0.0, 0.0, -1.2, -1.0,
          120.5, -33.25, 88.75, -88.75]
    struct.pack_into("<16f", buf, 0xA40, *vp)
    # code-like region: ASCII text bytes; as floats they are ~1e13 (fail FOV gate)
    code = b"VTP_GetEngineTraceClient; sub rsp,28h; mov [rcx+8],rdx; " * 40
    buf[0x1500:0x1500 + len(code)] = code
    got = []

    class Sink(object):
        def __call__(self, s):
            if s.strip().startswith("CAND"):
                got.append(s.strip())

    nA, nB, hits = scan_buffer(bytes(buf), "selftest", 0x10000, Sink())
    ok = (len(hits) == 2 and nA == 1 and nB == 1)
    addrs = sorted(h[1] for h in hits)
    ok = ok and addrs == [0x10000 + 0x540, 0x10000 + 0xA40]
    tiers = {h[1]: h[2] for h in hits}
    ok = ok and tiers.get(0x10000 + 0x540) == "A" and tiers.get(0x10000 + 0xA40) == "B"
    out("SELFTEST candidates=%d (expect 2) tierA=%d tierB=%d addrs=%s"
        % (len(hits), nA, nB, ["%#x" % a for a in addrs]))
    out("SELFTEST %s" % ("PASS" if ok else "FAIL"))
    return ok


def main(argv):
    out_path = OUT_DEF
    selftest_only = False
    region = None
    exe = EXE
    pkl = PICKLE
    snaps = list(SNAPS)
    for a in argv:
        if a == "--selftest-only":
            selftest_only = True
        elif a.startswith("--out="):
            out_path = a[6:]
        elif a.startswith("--exe="):
            exe = a[6:]
        elif a.startswith("--pickle="):
            pkl = a[9:]
        elif a.startswith("--snap="):
            snaps.append(a[7:])
        elif a.startswith("--region="):
            region = a[9:]
    out = Out(out_path)
    t0 = time.time()
    out("p74_matrix offline view-matrix canary scan  %s"
        % time.strftime("%Y-%m-%d %H:%M:%S"))
    out("offline + read-only; corpora per _ritual\\p73_assets.out (usable=4)")
    out("")
    if not selftest(out):
        out("RESULT: SELFTEST-FAIL (no corpus scanned)")
        out.close()
        return 1
    if selftest_only:
        out("RESULT: candidates=0 (selftest-only run, no corpus scanned)")
        out.close()
        return 0


    total = {}
    scanned_bytes = 0

    # ---- corpus 1: the exe ----------------------------------------------
    if os.path.exists(exe):
        data, imagebase, sizeofimage, secs = parse_pe(exe)
        out("CORPUS exe: %s imagebase=%#x sizeofimage=%#x"
            % (exe, imagebase, sizeofimage))
        for name, va, vsz, rsz, rp in secs:
            if name in (".data", ".rdata") and rsz >= 64:
                buf = data[rp:rp + rsz]
                scanned_bytes += len(buf)
                nA, nB, hits = scan_buffer(buf, "%s raw" % name,
                                           imagebase + va, out)
                total[name] = (nA, nB)
        # anti-example: RVA 0x22EE01 lives in .text (VTP_GetEngineTraceClient)
        off, secname = rva_to_off(secs, ANTI_RVA)
        out("")
        out("ANTI-EXAMPLE RVA %#x (ApexOffsets::VIEW_MATRIX today) -> section %s"
            % (ANTI_RVA, secname))
        if off is not None:
            m = list(struct.unpack_from("<16f", data, off))
            tier, score, di = canary(m)
            why = fail_reasons(m)
            out("  floats %s" % " ".join("%g" % v for v in m))
            if tier is None:
                out("  canary verdict: FAIL (%s)" % ("; ".join(why) or "row lengths"))
                out("  -> 0x022EE01 is code (VTP_GetEngineTraceClient), NOT a matrix;")
                out("     this is docs-gap-1: ESP stays empty until the matrix RVA is re-RE'd")
            else:
                out("  canary verdict: PASS tier=%s (unexpected!)" % tier)
        else:
            out("  RVA not file-backed (%s); floats unreadable from the file" % secname)
    else:
        out("CORPUS exe: MISSING (%s)" % exe)
    out("")

    # ---- corpus 2: dm11 pickle -------------------------------------------
    if os.path.exists(pkl):
        runs, base = load_pickle_runs(pkl)
        nb = sum(len(b) for _, b in runs)
        scanned_bytes += nb
        out("CORPUS dm11 pickle: %s runs>=%dB=%d bytes=%d (27/10 build)"
            % (pkl, MINRUN, len(runs), nb))
        a_sum = b_sum = 0
        for lo, b in runs:
            nA, nB, hits = scan_buffer(b, "dm11 run", lo, out)
            a_sum += nA
            b_sum += nB
        total["dm11"] = (a_sum, b_sum)
    else:
        out("CORPUS dm11 pickle: MISSING (%s)" % pkl)
    out("")

    # ---- corpus 3: p60 live snapshots ------------------------------------
    for snp in snaps:
        if os.path.exists(snp):
            pages = load_snap_pages(snp)
            nb = sum(len(b) for _, b in pages)
            scanned_bytes += nb
            out("CORPUS p60 snap: %s pages=%d bytes=%d"
                % (snp, len(pages), nb))
            a_sum = b_sum = 0
            for pg, b in pages:
                nA, nB, hits = scan_buffer(b, "snap page", pg, out)
                a_sum += nA
                b_sum += nB
            total[os.path.basename(snp)] = (a_sum, b_sum)
        else:
            out("CORPUS p60 snap: MISSING (%s)" % snp)
    out("")

    # ---- optional region (p75 protocol) ----------------------------------
    if region:
        path, _, vas = region.rpartition(":")
        va = int(vas, 0)
        if os.path.exists(path):
            buf = open(path, "rb").read()
            scanned_bytes += len(buf)
            out("CORPUS region: %s base=%#x bytes=%d" % (path, va, len(buf)))
            nA, nB, hits = scan_buffer(buf, "region", va, out)
            total["region"] = (nA, nB)
        else:
            out("CORPUS region: MISSING (%s)" % path)
        out("")

    nA_all = sum(v[0] for v in total.values())
    nB_all = sum(v[1] for v in total.values())
    parts = " ".join("%s:A=%d/B=%d" % (k, v[0], v[1]) for k, v in sorted(total.items()))
    out("elapsed %.1f s, scanned %.2f MB across corpora"
        % (time.time() - t0, scanned_bytes / 1048576.0))
    out("noise rate: %.3f candidates per MB (tierA %.3f/MB)"
        % ((nA_all + nB_all) / max(1.0, scanned_bytes / 1048576.0),
           nA_all / max(1.0, scanned_bytes / 1048576.0)))
    out("")
    out("NOTE: none of these corpora is a runtime .data dump (p73 E1); the")
    out("candidates above are structural/false-positive measurements on the real")
    out("build's bytes + live entity-cluster pages.  The live view matrix needs")
    out("the p75 rotate-90 differential over a live .data dump (lead approval).")
    out("RESULT: candidates=%d tierA=%d tierB=%d (%s)"
        % (nA_all + nB_all, nA_all, nB_all, parts if parts else "no corpus"))
    out("VERDICT: canary validated offline (selftest PASS, anti-example 0x22EE01 fails as code); "
        "candidates are canary noise-rate measurements on the p73 usable corpus, not the live matrix; "
        "live-matrix recovery deferred to the p75 protocol (rotate-90 differential, lead approval required)")
    out.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
