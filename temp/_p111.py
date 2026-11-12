r"""_p111.py -- PRE-FLIGHT before the next game session (PLAN rule 6).

One question, evidence only: *who* started DBUtilDrv2 in this boot, and is the box
clean enough to launch the game at all.  DSE read-back is `sc start apexdrv`
(577 = DSE ON with the unsigned driver present).  The only mutation is that start
attempt; if it unexpectedly succeeds, apexdrv is stopped again (R4 restore).

Writes temp\_p111_out.txt.  RESULT:/VERDICT: name the variable (R5).
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(os.path.dirname(HERE), "ext")
sys.path.insert(0, EXT)
import dumplive as dl   # noqa: E402

OUT = os.path.join(HERE, "_p111_out.txt")
PS = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]


def say(s):
    line = str(s)
    print(line, flush=True)
    with open(OUT, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def run(cmd, tmo=60):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=tmo)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except Exception as e:                    # noqa: BLE001
        return -1, repr(e)


def ps(script, tmo=90):
    return run(PS + [script], tmo)


def cap(cmd):
    rc, out = run(cmd)
    return rc, " ~~ ".join(ln.strip() for ln in out.splitlines() if ln.strip())


def main():
    if not dl.elevation():
        open(OUT, "w").close()
        say(dl.run_elevated('"%s"' % os.path.abspath(__file__)))
        return 0
    open(OUT, "w").close()
    say("=== p111 pre-flight %s ===" % dl.time.strftime("%Y-%m-%d %H:%M:%S"))
    say("elevated=1")

    # ---------------------------------------------------------------- session
    rc, out = ps("(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('s')")
    boot = out.strip().splitlines()[0] if out.strip() else "?"
    say("lastboot=%s" % boot)
    rc, out = ps("(Get-Date).ToString('s')")
    say("now=%s" % (out.strip().splitlines()[0] if out.strip() else "?"))
    # BootType: 0x0 full, 0x2 hybrid resume (fast startup).  If 0x2, a driver that was
    # RUNNING at shutdown is still RUNNING now and no SCM 7036 exists for it.
    rc, out = ps(
        "$e=Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Kernel-Boot';"
        "Id=27} -MaxEvents 2 -ErrorAction SilentlyContinue; "
        "$e | ForEach-Object { $_.TimeCreated.ToString('s')+' '+($_.Message -replace '\\s+',' ') }")
    for ln in (out or "").splitlines():
        if ln.strip():
            say("BOOTTYPE: " + ln.strip())

    # ---------------------------------------------------------------- drivers
    for svc in ("DBUtilDrv2", "gdrv3", "ApexDrv"):
        rc, out = cap(["sc.exe", "qc", svc])
        say("qc[%s] rc=%d :: %s" % (svc, rc, out))
        rc, out = cap(["sc.exe", "query", svc])
        say(" q[%s] rc=%d :: %s" % (svc, rc, out))
    rc, out = ps(
        "Get-CimInstance Win32_SystemDriver -Filter \"Name='DBUtilDrv2' OR Name='gdrv3'\" | "
        "ForEach-Object { $_.Name+' started='+$_.Started+' mode='+$_.StartMode+' path='+$_.PathName }")
    say("cim sysdrivers: " + " ~~ ".join(x.strip() for x in (out or "").splitlines() if x.strip()))

    # the file behind DBUtilDrv2: where it lives decides who owns it (kdu drops it in
    # System32\drivers; a vendor installer keeps it in its own dir)
    rc, out = ps(
        "$p='C:\\Windows\\System32\\drivers\\DBUtilDrv2.sys'; "
        "if (Test-Path $p) { $f=Get-Item $p; $v=$f.VersionInfo; "
        "$f.FullName+' size='+$f.Length+' mtime='+$f.LastWriteTime.ToString('s')+' ver='+$v.FileVersion; "
        "$sig=Get-AuthenticodeSignature $p; 'sigstatus='+$sig.Status+' signer='+$sig.SignerCertificate.Subject } "
        "else { 'ABSENT' }")
    say("dbutil file: " + " ~~ ".join(x.strip() for x in (out or "").splitlines() if x.strip()))

    # ------------------------------------------------------------------ origin
    # SCM 7045 (installed) / 7036 (state change) for either driver since boot.
    since = boot if boot != "?" else dl.time.strftime("%Y-%m-%dT%H:%M:%S")
    rc, out = ps(
        "Get-WinEvent -FilterHashtable @{LogName='System';Id=7045,7036;StartTime='%s'} "
        "-ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'DBUtil|gdrv3' } | "
        "ForEach-Object { $_.TimeCreated.ToString('s')+' id='+$_.Id+' '+($_.Message -replace '\\s+',' ') }"
        % since)
    hits = [x.strip() for x in (out or "").splitlines() if x.strip()]
    say("SCM events since boot: %d" % len(hits))
    for h in hits[:12]:
        say("  " + h)

    # who could have started it: live processes, tasks, Run keys
    rc, out = ps(
        "Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'kdu|dbutil|gdrv|armoury|asus|gigabyte|dell' } | "
        "ForEach-Object { $_.ProcessId.ToString()+' '+$_.Name+' :: '+$_.CommandLine }")
    procs = [x.strip() for x in (out or "").splitlines() if x.strip()]
    say("procs(kdu/dbutil/vendor)=%d" % len(procs))
    for p in procs[:10]:
        say("  " + p)
    rc, out = ps(
        "schtasks.exe /query /fo csv /v 2>$null | Select-String -Pattern 'DBUtil|kdu|apexdrv|gdrv' | "
        "ForEach-Object { ($_.Line -split '\",\"')[0..3] -join ',' }")
    tasks = [x.strip() for x in (out or "").splitlines() if x.strip()]
    say("tasks matching=%d" % len(tasks))
    for t in tasks[:8]:
        say("  " + t)
    rc, out = ps(
        "'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run','HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run' | "
        "ForEach-Object { $k=$_; (Get-Item $k -ErrorAction SilentlyContinue).GetValueNames() | "
        "ForEach-Object { $k+'\\'+$_+'='+(Get-ItemProperty $k -Name $_).$_ } } | "
        "Select-String -Pattern 'DBUtil|kdu|apex|gdrv|gigabyte|armoury'")
    for r in [x.strip() for x in (out or "").splitlines() if x.strip()][:8]:
        say("  run: " + r)

    # --------------------------------------------------------------- DSE probe
    rc, out = cap(["sc.exe", "start", "ApexDrv"])
    say("RESULT: dse_probe start_apexdrv rc=%d :: %s" % (rc, out))
    dse_on = (rc == 577)
    say("RESULT: dse=%s (577=ON+unsigned present)" % ("ON" if dse_on else ("OFF-STARTED" if rc == 0 else "UNKNOWN")))
    if rc == 0:
        rc, out = cap(["sc.exe", "query", "ApexDrv"])
        say(" post-start q: rc=%d :: %s" % (rc, out))
        rc, out = cap(["sc.exe", "stop", "ApexDrv"])
        say(" RESTORE stop rc=%d :: %s" % (rc, out))
        rc, out = cap(["sc.exe", "query", "ApexDrv"])
        say(" post-restore q: rc=%d :: %s" % (rc, out))

    # ---------------------------------------------------------------- verdict
    rc, qd = cap(["sc.exe", "query", "DBUtilDrv2"])
    dbutil_running = "RUNNING" in qd
    say("RESULT: dbutil_running=%d scm_events=%d" % (dbutil_running, len(hits)))
    if dbutil_running and len(hits) == 0:
        say("RESULT: dbutil_origin=survived_shutdown (no SCM start in this boot -> hybrid/fast-startup resume)")
        say("STATE: box=DIRTY (DBUtilDrv2 resident, DSE %s) -> real restart required before the game"
            % ("ON" if dse_on else "?"))
        say("VERDICT: PASS - pre-flight answered")
    elif dbutil_running and hits:
        say("RESULT: dbutil_origin=started_this_boot (see SCM 7036/7045 above)")
        say("STATE: box=DIRTY (DBUtilDrv2 resident) -> real restart required before the game")
        say("VERDICT: PASS - pre-flight answered")
    elif not dbutil_running:
        say("RESULT: dbutil_origin=absent")
        say("STATE: box=CLEAN (DBUtilDrv2 stopped, DSE %s)" % ("ON" if dse_on else "?"))
        say("VERDICT: PASS - box clean, game session allowed")
    say("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
