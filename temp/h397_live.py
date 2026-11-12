r"""h397 current-match one-variable scan: 4KiB MapK (not 64KiB callers).
If the standard Proc pool tag is absent on this build, the bounded PML4-shape
walks from the established helper still never trust arbitrary qwords.
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ext"))
import dumplive as dl
import qk_bridge

OUT = os.path.join(ROOT, "temp", "h397_live.txt")

def say(s):
    print(s, flush=True)
    with open(OUT, "a", encoding="ascii") as f:
        f.write(s + "\n")

open(OUT, "w").close()
if not dl.elevation():
    sys.exit(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
pid = qk_bridge.find_pid()[0]
say("H397 current pid=%d time=%s" % (pid, time.strftime("%Y-%m-%d %H:%M:%S")))
scan = qk_bridge.ObjectScan()
try:
    result = scan.bind(pid, say, budget=150.0)
    say("VERDICT: %s" % ("PASS" if result else "BLOCKED"))
    say("SC=query verified existing gdrv3, no process writes/new driver")
finally:
    scan.close()