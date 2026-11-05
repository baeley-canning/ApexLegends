r"""p73_victim.py -- hold a process open so its page tables can be calibrated."""
import os
import sys
import time

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_p73_victim.txt")
with open(out, "w", encoding="utf-8") as f:
    f.write("%d\n" % os.getpid())
time.sleep(float(sys.argv[1]) if len(sys.argv) > 1 else 180)
