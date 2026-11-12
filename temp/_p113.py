r"""_p113.py -- PROBE: get DBUtilDrv2 off the box without a reboot.

p111 (11:52) proved DBUtilDrv2 is RUNNING with ZERO SCM start events in a BootType 0x0
boot, and the two unnamed 7036 "Driver load" events at 11:23:08 plus a live
GigabyteUpdateService.exe (pid 5168) point at the Gigabyte suite loading it via
NtLoadDriver at logon.  So the old pre-flight rule ("reboot clears it") is wrong: the
loader would just do it again.  Order is starter first, then the driver.

Variable: who/starter gets stopped.  Restores are recorded in the same run (R4) and the
driver is signed (WHCP) so it restarts under DSE ON.  Writes temp\_p113_out.txt.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import dumplive as dl   # noqa: E402

OUT = os.path.join(HERE, "_p113_out.txt")
SVC = "GigabyteUpdateService"


def say(s):
    line = str(s)
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def cap(cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        return p.returncode, " ~~ ".join(x.strip() for x in
                                        ((p.stdout or "") + (p.stderr or "")).splitlines() if x.strip())
    except Exception as e:                 # noqa: BLE001
        return -1, repr(e)


def state(name):
    rc, out = cap(["sc.exe", "query", name])
    for tok in ("RUNNING", "STOPPED", "STOP_PENDING", "1060", "1052"):
        if tok in out:
            return tok
    return "rc=%d" % rc


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== p113 dbutil unload %s ===" % dl.time.strftime("%Y-%m-%d %H:%M:%S"))
    rc, out = cap(["sc.exe", "qc", SVC])
    say("qc[%s] rc=%d :: %s" % (SVC, rc, out))
    if rc != 0:
        say("RESULT: starter_absent=%d (service name guess wrong - look in p111 procs)" % rc)

    pre = {n: state(n) for n in (SVC, "DBUtilDrv2", "gdrv3")}
    say("PRE: %s" % pre)
    say("RESTORE: sc start %s; sc start DBUtilDrv2" % SVC)
    if "RUNNING" in pre[SVC]:
        rc, out = cap(["sc.exe", "stop", SVC])
        say("stop %s rc=%d :: %s" % (SVC, rc, out))
        dl.time.sleep(3)
        say("  POST-starter: %s = %s" % (SVC, state(SVC)))
    else:
        say("starter not running - nothing to stop")
    # does killing the loader take the driver with it?  most likely no (no unload path)
    say("  after starter stop, DBUtilDrv2 = %s" % state("DBUtilDrv2"))
    if "RUNNING" in state("DBUtilDrv2"):
        rc, out = cap(["sc.exe", "stop", "DBUtilDrv2"])
        say("RESULT: stop_dbutil rc=%d :: %s" % (rc, out))
        dl.time.sleep(3)
    post = {n: state(n) for n in (SVC, "DBUtilDrv2", "gdrv3")}
    say("POST: %s" % post)
    rc, out = cap(["sc.exe", "start", "ApexDrv"])   # DSE read-back, fails 577 when ON
    say("RESULT: dse_after_dbutil_stop apexdrv_rc=%d (577=DSE ON)" % rc)
    if post["DBUtilDrv2"] == "STOPPED":
        say("RESULT: dbutil=STOPPED, starter=%s -> box CLEAN without reboot" % post[SVC])
        say("STATE: box=%s" % ("CLEAN" if rc == 577 else "CLEAN-DSE-UNKNOWN"))
        say("VERDICT: PASS - ready for the game gate, gdrv3 only")
    else:
        say("RESULT: dbutil=%s starter=%s (1052 = no unload path -> reboot required)"
            % (post["DBUtilDrv2"], post[SVC]))
        say("STATE: box=DIRTY")
        say("VERDICT: FAIL - unload blocked; reboot with the starter stopped")
    say("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
