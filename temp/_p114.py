r"""_p114.py -- PROBE: make the *next* reboot actually clean the box.

p113 (11:54): `sc stop DBUtilDrv2` = 1052 (no unload path) and stopping
GigabyteUpdateService does not unload it.  The starter is AUTO_START, so a plain reboot
would load it straight back at logon (p111 already proved the load leaves no SCM event:
NtLoadDriver, not `sc start`).

Variable: GigabyteUpdateService Start type AUTO(2) -> DEMAND(3).  Reversible in one
command, saved in temp\_p114_restore.txt.  No reboot here (R2).
Writes temp\_p114_out.txt.  RESULT/VERDICT name the variable.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import dumplive as dl   # noqa: E402

OUT = os.path.join(HERE, "_p114_out.txt")
REST = os.path.join(HERE, "_p114_restore.txt")
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


def starttype(name):
    rc, out = cap(["sc.exe", "qc", name])
    if "START_TYPE" in out:
        return out.split("START_TYPE", 1)[1].split("~~")[0].strip()
    return "rc=%d :: %s" % (rc, out[:120])


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== p114 starter start-type %s ===" % dl.time.strftime("%Y-%m-%d %H:%M:%S"))
    before = starttype(SVC)
    say("PRE: %s START_TYPE %s" % (SVC, before))
    if "AUTO_START" not in before:
        say("RESULT: already non-auto - nothing changed")
        say("VERDICT: PARTIAL - start type was %s" % before)
        return 0
    with open(REST, "w", encoding="utf-8") as f:
        f.write("restore: sc config %s start= auto\n" % SVC)
        f.write("note: p114 %s set DEMAND so a reboot clears DBUtilDrv2 (untracked\n"
                "NtLoadDriver at logon, no SCM event). Gigabyte Control Center only loses\n"
                "its onlogon updater until this is undone.\n" % dl.time.strftime("%Y-%m-%d %H:%M:%S"))
    rc, out = cap(["sc.exe", "config", SVC, "start=", "demand"])
    say("RESULT: config_demand rc=%d :: %s" % (rc, out))
    after = starttype(SVC)
    say("POST: %s START_TYPE %s" % (SVC, after))
    rc, out = cap(["sc.exe", "stop", SVC])
    say("stop %s rc=%d :: %s" % (SVC, rc, out))
    rc, out = cap(["sc.exe", "query", SVC])
    say("q rc=%d :: %s" % (rc, out))
    ok = ("DEMAND" in after) and ("STOPPED" in out)
    say("RESULT: start_type %s -> %s" % (before, after))
    say("STATE: box=DIRTY until reboot (DBUtilDrv2 has no unload path)")
    if ok:
        say("VERDICT: PASS - reboot now clears DBUtilDrv2 and the starter will not reload it")
        say("AFTER REBOOT: run temp\\_p111.py again, expect dbutil_running=0 / box=CLEAN")
        say("UNDO: sc config %s start= auto" % SVC)
        return 0
    say("VERDICT: FAIL - start type or stop did not take")
    return 3


if __name__ == "__main__":
    sys.exit(main())
