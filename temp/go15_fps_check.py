# -*- coding: utf-8 -*-
"""go15_fps_check.py -- M3.0 render-cap ladder on the synthetic (fake) lane.

Stage: RENDER-FEEL -- the pixel this can change is a box steady at 144 Hz.
One variable (R5): qk_live's new --fps= flag. Everything is synthetic:
--fake means no game, no driver, no elevation (qk_live's own contract),
so this is host-safe infrastructure under R1/R8, NOT a game-half probe.
Runs must be launched DETACHED (canon: _ritual/detach_run.ps1).

Reads back temp/go15_fps_check.txt; verdict names the variable (--fps).
Cases: baseline (default 60) -> --fps=144 -> --fps=0 (uncapped ceiling),
plus py_compile and the canonical 13/13 regression suite as gates.
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
OUT = os.path.join(HERE, "go15_fps_check%s.txt"
                   % os.environ.get("GO15_SUFFIX", ""))

OUT_F = None


def say(s):
    OUT_F.write(str(s) + "\n")
    OUT_F.flush()


def run_fake(tag, extra, secs=8.0):
    """One synthetic run; return the best fps its stop banner reports."""
    cmd = [sys.executable, QK, "--fake", "--seconds=%d" % int(round(secs))] + extra
    say("--- case %-14s %s" % (tag, " ".join(extra) or "(defaults)"))
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT,
                           timeout=secs * 6 + 120)
    except subprocess.TimeoutExpired as e:
        say("TIMEOUT %s after %.0fs" % (tag, e.timeout or 0))
        return 0.0
    for line in (p.stdout or "").splitlines():
        if line.strip():
            say("  out: " + line.strip())
    if p.stderr and p.stderr.strip():
        say("  err: " + p.stderr.strip())
    stops = re.findall(r"fps=([0-9]+(?:\.[0-9]+)?)", p.stdout or "")
    fps = max([float(x) for x in stops], default=0.0)
    say("MEASURED %s fps_max=%.1f" % (tag, fps))
    return fps


def main():
    global OUT_F
    OUT_F = open(OUT, "w", encoding="utf-8")
    rc = 0
    say("go15_fps_check start %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
    say("interpreter: %s" % sys.executable)
    try:
        c = subprocess.run([sys.executable, "-m", "py_compile", QK],
                           capture_output=True, text=True)
        say("gate py_compile rc=%d %s" % (c.returncode, (c.stderr or "").rstrip()))
        if c.returncode:
            rc = 2
        g = subprocess.run([sys.executable, REG], capture_output=True, text=True,
                           cwd=ROOT, timeout=900)
        tails = [ln for ln in (g.stdout or "").splitlines() if ln.strip()][-6:]
        say("gate regression rc=%d tail:" % g.returncode)
        for ln in tails:
            say("  " + ln)
        if g.returncode:
            rc = rc or 3
        base = run_fake("baseline_60", [])
        hi = run_fake("fps_144", ["--fps=144"])
        unc = run_fake("fps_0_uncapped", ["--fps=0"])
        say("--- judge: variable = --fps ---")
        bits = []
        if base >= 50.0:
            bits.append("BASELINE_OK(%.1f)" % base)
        else:
            bits.append("BASELINE_ANOMALY(%.1f<50)" % base)
        if hi >= 130.0:
            bits.append("FPS144_HOLD(%.1f)" % hi)
        else:
            bits.append("FPS144_SHORT(%.1f<130)" % hi)
        if unc > hi + 5.0:
            bits.append("UNCAPPED_CEILING=%.1f_python_should_not_be_the_ceil?"
                        % unc)
        else:
            bits.append("UNCAPPED_NO_GAIN_OVER_144(%.1f<= %.1f+5: loop-bound)"
                        % (unc, hi))
        say("RESULT: fps variable=--fps baseline=%.1f fps144=%.1f uncapped=%.1f"
            % (base, hi, unc))
        say("VERDICT: %s rc=%d" % (" ".join(bits), rc))
    except Exception:                                  # noqa: BLE001
        import traceback
        say(traceback.format_exc())
        rc = 9
    say("go15_fps_check end rc=%d" % rc)
    OUT_F.close()
    sys.exit(rc)


if __name__ == "__main__":
    main()
