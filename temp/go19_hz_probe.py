# -*- coding: utf-8 -*-
"""go19_hz_probe.py -- M3.1 read-path cadence ladder on the synthetic lane.

Stage: RENDER-FEEL -- the pixel this can change is a box steady at the
configured read cadence (hud hz=N).  One variable (R5): qk_live's --hz= flag.
Everything synthetic: --fake means no game, no driver, no elevation, so this
is host-safe infrastructure under R1/R8, NOT a game-half probe.

Instrument: the additive `read-cadence: ticks=N eff_hz=E target_hz=T` line
qk_live emits next to the stop banner; the ladder judges TARGET ACCEPTANCE
(sanitizer admits 120/144), PACING ACCURACY per rung, the legacy fallback
(bogus --hz=90 -> 20), and fps/rate coexistence.  Baseline-before-edit state
was captured by temp/go19_gates.py (note: its pre-tagged run raced the edit
sweep by seconds; post-tagged gates on the FINAL bytes are the binding gate).

Runs DETACHED per canon (temp/go19_hz_probe.py -> _go19_hz_probe console);
evidence temp/_go19_hz_probe.txt; verdict names the variable (--hz).
Cases: default(20) -> 60 -> 144(+--fps=0) -> bogus90-fallback -> fps60-coexist.
"""
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
QK = os.path.join(ROOT, "ext", "qk_live.py")
REG = os.path.join(ROOT, "temp", "qk_live_regression.py")
_sfx = ""
for _a in sys.argv[1:]:
    if _a.startswith("--tag="):
        _sfx = "_" + _a.split("=", 1)[1].strip()
OUT = os.path.join(HERE, "_go19_hz_probe%s.txt" % _sfx)

OUT_F = None

CAD = re.compile(r"read-cadence: ticks=(\d+) eff_hz=([0-9.]+) target_hz=(\d+)")

CASES = (
    # tag, extra argv, expected target, (eff_min, eff_max)
    ("default_20", [], 20, (14.0, 26.0)),
    ("hz_60", ["--hz=60"], 60, (45.0, 66.0)),
    ("hz_144_uncapped", ["--hz=144", "--fps=0"], 144, (100.0, 170.0)),
    ("bogus_90_fallback", ["--hz=90"], 20, (14.0, 26.0)),
    ("fps60_coexist_120", ["--hz=120", "--fps=60"], 120, (45.0, 70.0)),
)


def say(s):
    OUT_F.write(str(s) + "\n")
    OUT_F.flush()


def run_case(tag, extra, secs=8.0):
    """One --fake run; return (fps, eff_hz, target_hz) from its output."""
    cmd = ([sys.executable, QK, "--fake", "--seconds=%d" % int(round(secs))]
           + extra)
    say("--- case %-18s %s" % (tag, " ".join(extra) or "(defaults)"))
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT,
                           timeout=secs * 6 + 120)
    except subprocess.TimeoutExpired as e:
        say("TIMEOUT %s after %.0fs" % (tag, e.timeout or 0))
        return 0.0, 0.0, -1
    for line in (p.stdout or "").splitlines():
        if line.strip():
            say("  out: " + line.strip())
    if p.stderr and p.stderr.strip():
        say("  err: " + p.stderr.strip()[-300:])
    fps_list = [float(x) for x in
                re.findall(r"fps=([0-9]+(?:\.[0-9]+)?)", p.stdout or "")]
    m = CAD.search(p.stdout or "")
    if m:
        eff, tgt = float(m.group(2)), int(m.group(3))
    else:
        eff, tgt = 0.0, -1
    say("MEASURED %s fps=%.1f eff_hz=%.1f target_hz=%d"
        % (tag, max(fps_list, default=0.0), eff, tgt))
    return max(fps_list, default=0.0), eff, tgt


def main():
    global OUT_F
    OUT_F = open(OUT, "w", encoding="utf-8")
    rc = 0
    say("go19_hz_probe start %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
    say("interpreter: %s" % sys.executable)
    try:
        c = subprocess.run([sys.executable, "-m", "py_compile", QK],
                           capture_output=True, text=True)
        say("gate py_compile rc=%d %s" % (c.returncode, (c.stderr or "").rstrip()))
        if c.returncode:
            rc = 2
        g = subprocess.run([sys.executable, REG], capture_output=True,
                           text=True, cwd=ROOT, timeout=900)
        tails = [ln for ln in (g.stdout or "").splitlines() if ln.strip()][-3:]
        say("gate regression rc=%d tail:" % g.returncode)
        for ln in tails:
            say("  " + ln)
        if g.returncode:
            rc = rc or 3
        bits = []
        for tag, extra, want_t, (lo, hi) in CASES:
            fps, eff, tgt = run_case(tag, extra)
            if tgt != want_t:
                bits.append("%s_TARGET_BAD(%d!=%d)" % (tag.upper(), tgt, want_t))
                rc = rc or 4
            elif not (lo <= eff <= hi):
                bits.append("%s_PACING_OOB(%.1f outside [%.1f,%.1f])"
                            % (tag.upper(), eff, lo, hi))
                rc = rc or 5
            else:
                bits.append("%s_OK(%.1f@%d)" % (tag.upper(), eff, tgt))
        say("RESULT: --hz variable= read-path cadence target/eff per case above")
        say("VERDICT: %s rc=%d" % (" ".join(bits), rc))
    except Exception:                                  # noqa: BLE001
        import traceback
        say(traceback.format_exc())
        rc = 9
    say("go19_hz_probe end rc=%d" % rc)
    OUT_F.close()
    sys.exit(rc)


if __name__ == "__main__":
    main()
