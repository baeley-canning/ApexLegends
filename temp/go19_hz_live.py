# -*- coding: utf-8 -*-
"""go19_hz_live.py -- M3.1 live-wire leg: --hz cadence BESIDE the real game window.

PURPOSE: prove the cadence plumbing behaves in run-mode against a live window
(the M3 lever's wired-in-place half).  Honesty contract (R9): with the census
quarantined (gate=player_type_unverified, SECTION 226) ZERO boxes will draw;
this leg certifies cadence + overlay stability, NOT in-game rendering.
Verdict therefore grades: cadence LIVE-PROVEN / boxes=SKIPPED-quarantined.

Controls (pre-registered, judged from files only):
  C1 game alive immediately BEFORE the run (else SKIPPED, rc=4)
  C2 qk_live --run --hz=144 --fps=60 --seconds=45 exits cleanly (DETACHED)
  C3 read-cadence line from the appended lane shows target_hz=144
  C4 game still alive AFTER the run
  C5 (informational) banner fps recorded

Transport hygiene: run-mode uses the same parasitic ephemeral gio reader the
B4 audit cleared (idle handles=0 posture); NOTHING is loaded or unloaded here.
UAC note: run-mode self-relaunches elevated (dl.run_elevated) on first use.
"""
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
QK = os.path.join(ROOT, "ext", "qk_live.py")
LANE = os.path.join(ROOT, "temp", "qk_live_out.txt")
OUT = os.path.join(HERE, "_go19_hz_live.txt")

CAD = re.compile(r"read-cadence: ticks=(\d+) eff_hz=([0-9.]+) target_hz=(\d+)")
SECS = int(os.environ.get("GO19_LIVE_SECS", "45"))


def game_alive():
    r = subprocess.run(["tasklist", "/FI", "IMAGENAME eq r5apex_dx12.exe",
                        "/FO", "CSV", "/NH"],
                       capture_output=True, text=True)
    for ln in (r.stdout or "").splitlines():
        if "r5apex_dx12" in ln:
            try:
                return int(ln.split('","')[1])
            except (IndexError, ValueError):
                return -1
    return 0


def lane_tail(n=40):
    try:
        with open(LANE, "r", encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return []
    return lines[-n:]


def main():
    rc = 0
    bits = []
    with open(OUT, "w", encoding="utf-8") as f:
        def say(s):
            f.write(str(s) + "\n")
            f.flush()

        say("go19_hz_live start %s" % time.strftime("%Y-%m-%d %H:%M:%S"))
        pid = game_alive()
        if not pid:
            say("RESULT: C1 game not running -> SKIPPED (R9)")
            say("VERDICT: PARTIAL cadence-live=SKIPPED(no_game) rc=4")
            sys.exit(4)
        say("C1: game alive pid=%d" % pid)

        mark = len(lane_tail(200000))            # grow-only lane; remember length
        cmd = [sys.executable, QK, "--run", "--hz=144", "--fps=60",
               "--seconds=%d" % SECS]
        say("C2: launching detached-equivalent foreground child: %s"
            % " ".join(cmd))
        t0 = time.time()
        try:
            p = subprocess.run(cmd, capture_output=True, text=True,
                               cwd=ROOT, timeout=SECS * 6 + 240)
            rc_child, tail = p.returncode, (p.stdout or "")
        except subprocess.TimeoutExpired:
            rc_child, tail = 124, ""
        dt = time.time() - t0
        say("C2: child rc=%d wall=%.1fs" % (rc_child, dt))
        for ln in tail.splitlines():
            if ln.strip():
                say("  out: " + ln.strip())

        new_lines = []
        try:
            with open(LANE, "r", encoding="utf-8", errors="replace") as fh:
                all_lines = fh.read().splitlines()
            new_lines = all_lines[mark:] if len(all_lines) >= mark else all_lines
        except OSError:
            pass
        say("lane rows appended: %d" % len(new_lines))
        for ln in new_lines[-8:]:
            say("  lane| " + ln)
        joined = "\n".join(tail.splitlines() + new_lines)
        mcad = CAD.findall(joined)
        if mcad:
            ticks, eff, tgt = mcad[-1]
            ticks, eff, tgt = int(ticks), float(eff), int(tgt)
            say("C3: cadence line ticks=%d eff_hz=%.1f target_hz=%d"
                % (ticks, eff, tgt))
            if tgt == 144:
                bits.append("C3_TARGET_144_OK")
            else:
                bits.append("C3_TARGET_BAD(%d)" % tgt)
                rc = rc or 5
        else:
            say("C3: MISSING read-cadence line in evidence")
            bits.append("C3_MISSING")
            rc = rc or 5
        if rc_child in (0, 4):
            # rc 0 = qk_live clean stop; rc 4 = its coded PARTIAL verdict
            # (SKIPPED in-game rendering under the section-226 quarantine).
            # Both mean the 45 s timed run shut down gracefully; treating
            # rc==0 as the sole success mis-scored a correct live stop.
            bits.append("C2_CLEAN_EXIT(rc=%d)" % rc_child)
        else:
            bits.append("C2_EXIT=%d" % rc_child)
            rc = rc or 6
        pid_after = game_alive()
        if pid_after:
            say("C4: game alive after run pid=%d" % pid_after)
            bits.append("C4_GAME_STABLE")
        else:
            say("C4: GAME NOT RUNNING AFTER RUN")
            bits.append("C4_GAME_GONE")
            rc = rc or 7
        say("C5: banner fps excerpt above (informational)")
        say("RESULT: --hz live-wire beside pid %s; boxes=0 expected "
            "(section-226 quarantine)" % pid)
        say("VERDICT: %s rc=%d" % (" ".join(bits), rc))
    sys.exit(rc)


if __name__ == "__main__":
    main()
