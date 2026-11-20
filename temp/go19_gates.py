# -*- coding: utf-8 -*-
"""go19_gates.py -- M3.1 pre/post edit gate-runner for the --hz cadence ladder.

Captures the four standing gates as files (R3: verdicts come from files, never
from console echo).  Tag selects the slot so pre-edit and post-edit states
never overwrite each other (R5: new number, never overwrite):

    GO19_TAG=pre   -> temp/_go19_gates_pre.txt
    GO19_TAG=post  -> temp/_go19_gates_post.txt

Gates: py_compile(ext/qk_live.py), canonical regression 13/13
(temp/qk_live_regression.py), expiry probe (temp/go16_expiry_probe.py),
field probe (temp/go17_field_probe.py).  Zero game/driver interaction --
host-safe infrastructure under R1/R8.  >5 s canon: launch DETACHED via
_ritual/detach_run.ps1.
"""
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
QK = os.path.join(ROOT, "ext", "qk_live.py")
TAG = "pre"
for _a in sys.argv[1:]:
    if _a.startswith("--tag="):
        TAG = _a.split("=", 1)[1].strip() or "pre"
OUT = os.path.join(HERE, "_go19_gates_%s.txt" % TAG)

GATES = (
    ("pycompile", [sys.executable, "-m", "py_compile", QK]),
    ("canonical", [sys.executable, os.path.join(HERE, "qk_live_regression.py")]),
    ("expiry", [sys.executable, os.path.join(HERE, "go16_expiry_probe.py")]),
    ("field", [sys.executable, os.path.join(HERE, "go17_field_probe.py")]),
)

rc_all = 0


def main():
    global rc_all
    with open(OUT, "w", encoding="utf-8") as f:
        def say(s):
            f.write(str(s) + "\n")
            f.flush()

        say("go19_gates[%s] start %s" % (TAG, time.strftime("%Y-%m-%d %H:%M:%S")))
        for name, cmd in GATES:
            t0 = time.time()
            try:
                p = subprocess.run(cmd, capture_output=True, text=True,
                                   cwd=ROOT, timeout=900)
                rc, tail = p.returncode, (p.stdout or "")
            except subprocess.TimeoutExpired:
                rc, tail = 124, ""
            dt = time.time() - t0
            lines = [ln.strip() for ln in tail.splitlines() if ln.strip()]
            say("gate %-9s rc=%-3d %5.1fs" % (name, rc, dt))
            for ln in lines[-4:]:
                say("  | " + ln)
            if (p.stderr or "").strip():
                say("  err: " + (p.stderr or "").strip()[-400:])
            rc_all = rc_all or rc
        say("GATES: %s rc=%d" % (TAG, rc_all))
        say("go19_gates[%s] end %s" % (TAG, time.strftime("%H:%M:%S")))
    sys.exit(rc_all)


if __name__ == "__main__":
    main()
