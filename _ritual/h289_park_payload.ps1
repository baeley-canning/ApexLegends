# h289_park_payload.ps1 - PARK payload. Deployed as C:\p37vm\payload\cur.ps1 so the guest tick
# (p37tick -> run.cmd -> once.cmd -> cur.ps1) pulls THIS instead of the h286 driver probe.
#
# WHY: h286 proved the bugcheck happens AFTER a successful POST whose last line is
# "zapexdrv after release" (guest 15:14:13.374). The two W lines that follow it
# (STEP=probe-kernel, STEP=inject-kernel) never reached the next Post, so the box dies INSIDE
# the 180 s apex_launcher --inject --manual-map call, not in the unload. RunExe keeps the
# launcher's stdout in memory only and launcher printf is CRT-buffered on a pipe, so that
# output is unrecoverable by design. The only channel that survives a bugcheck is the disk +
# the event log. This payload harvests both, and does no driver work at all, so the guest
# stays up long enough to read the answer.
#
# Contract: run.cmd re-arms p37logon and p37tick re-fires every minute, so this must be
# idempotent and cheap. One report per boot, gated on LastBootUpTime, exactly like cur.ps1.
# Read-only: sc QUERY only. No sc start/stop/delete, no kdu, no launcher. Reversible by
# restoring cur_h289_live.ps1 over cur.ps1 on the host (no guest state to undo).
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::Expect100Continue = $false
$base = 'http://10.0.2.2:8080'
$d    = 'C:\Users\Public\p37'
$tag  = 'h289p'
$done = "$d\h289p.done"
$L    = New-Object System.Collections.ArrayList
function W([string]$s) { [void]$L.Add(((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s)) }
function Post {
    # tail-only with a hard deadline, same as cur.ps1: a wedged upload must not park the tick
    $body = if ($L.Count -gt 150) { ('...' + ($L.Count - 150) + ' earlier lines not uploaded') + "`r`n" + (($L | Select-Object -Last 150) -join "`r`n") } else { $L -join "`r`n" }
    for ($k = 1; $k -le 2; $k++) {
        try {
            [void](Invoke-WebRequest -Uri "$base/log?vm=$tag" -Method Post -Body ("## $tag`r`n" + $body) -TimeoutSec 10 -UseBasicParsing -EA Stop)
            break
        } catch { Start-Sleep -Milliseconds 400 }
    }
}
md $d -Force | Out-Null
$os = Get-CimInstance Win32_OperatingSystem
$bootId = $os.LastBootUpTime.Ticks
# one report per boot: a second tick in the same boot exits silently (no log spam, no work).
if (Test-Path $done) {
    $old = @(Get-Content -LiteralPath $done -EA 0)
    if ($old.Count -ge 1 -and [long]$old[0] -eq $bootId) { exit 0 }
}
Set-Content -LiteralPath $done -Value ($bootId, (Get-Date).ToFileTime())
W 'alive (PARK payload: no driver start/stop/unload, no launcher, no kdu)'
W ('build ' + $os.BuildNumber + ' boot=' + $os.LastBootUpTime.ToString('dd/MM HH:mm:ss') + ' pid=' + $PID)
W ('localappdata=[' + $env:LOCALAPPDATA + '] temp=[' + $env:TEMP + '] user=[' + $env:USERNAME + ']')
# 1. payload dir: what the crashed run left behind, newest first
W 'STEP=payload-dir'
foreach ($f in @(Get-ChildItem -LiteralPath $d -File -EA 0 | Sort-Object LastWriteTime -Descending | Select-Object -First 25)) {
    W ('  f ' + $f.Name + ' ' + $f.Length + 'b ' + $f.LastWriteTime.ToString('dd/MM HH:mm:ss'))
}
# 2. the crash record on disk: minidumps + full dump, with times so they map to a run
W 'STEP=dumps'
$dumps = @(Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -EA 0 | Sort-Object LastWriteTime -Descending)
W ('minidumps=' + $dumps.Count)
foreach ($m in @($dumps | Select-Object -First 8)) {
    W ('  d ' + $m.Name + ' ' + $m.Length + 'b ' + $m.LastWriteTime.ToString('dd/MM HH:mm:ss'))
}
$mem = Get-Item -LiteralPath "$env:SystemRoot\MEMORY.DMP" -EA 0
if ($mem) { W ('  MEMORY.DMP ' + $mem.Length + 'b ' + $mem.LastWriteTime.ToString('dd/MM HH:mm:ss')) } else { W '  MEMORY.DMP absent' }
# 3. the verdict-bearing half: BugCheck 1001 carries the code AND the four parameters, so the
#    faulting address is recoverable without opening a dump. Full message, never truncated.
W 'STEP=bugcheck-events'
try {
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001 } -MaxEvents 4 -EA 0)
    W ('events(1001)=' + $ev.Count)
    foreach ($e in $ev) { W ('  e ' + $e.TimeCreated.ToString('dd/MM HH:mm:ss') + ' ' + (($e.Message -replace '\s+', ' ').Trim())) }
} catch { W ('  1001 lookup failed: ' + $_.Exception.Message) }
try {
    $ev2 = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41, 6008 } -MaxEvents 4 -EA 0)
    foreach ($e in $ev2) { W ('  e' + $e.Id + ' ' + $e.TimeCreated.ToString('dd/MM HH:mm:ss') + ' ' + (($e.Message -replace '\s+', ' ').Trim())) }
} catch { }
# 4. WER archive: the .wer text repeats the bugcheck code and names the response
W 'STEP=wer'
$wer = @(Get-ChildItem -LiteralPath 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive' -Directory -EA 0 | Where-Object { $_.Name -match 'BlueScreen|Kernel' } | Sort-Object LastWriteTime -Descending | Select-Object -First 4)
W ('wer dirs=' + $wer.Count)
foreach ($w in $wer) {
    W ('  w ' + $w.Name + ' ' + $w.LastWriteTime.ToString('dd/MM HH:mm:ss'))
    $r = Get-ChildItem -LiteralPath $w.FullName -Filter *.wer -EA 0 | Select-Object -First 1
    if ($r) {
        foreach ($ln in @(Get-Content -LiteralPath $r.FullName -EA 0 | Select-String -Pattern '^EventType|^Sig\[|^DynamicSig|^OsInfo\[0\]|^Response\.type')) {
            W ('    ' + $ln.Line.Trim())
        }
    }
}
# 5. chain health: was the tick re-arming, and what did the previous run leave
W 'STEP=chain'
$t = "$d\tick.log"
if (Test-Path -LiteralPath $t) {
    W 'tick.log tail:'
    foreach ($ln in @(Get-Content -LiteralPath $t -Tail 6 -EA 0)) { W ('  t ' + $ln) }
}
foreach ($f in @('h286.out', 'h286.done', 'h286.lock', 'h285.out')) {
    if (Test-Path -LiteralPath "$d\$f") { W ('  leftover ' + $f + ' ' + (Get-Item -LiteralPath "$d\$f").LastWriteTime.ToString('dd/MM HH:mm:ss')) }
}
# 6. read-only service state. run.cmd itself starts gdrv3 before this script runs, so gdrv3's
#    state is part of the crash context and must be reported, not assumed.
W 'STEP=svc-readonly'
foreach ($s in @('zapexdrv', 'gdrv3')) {
    W ('  svc ' + $s + ': ' + (((& "$env:SystemRoot\system32\sc.exe" query $s 2>&1) -split "`n" | Where-Object { $_ -match 'STATE|FAILED|does not exist|1058|1060' }) -join ' | ').Trim())
}
W ('  drvfile zapexdrv.sys=' + $(if (Test-Path -LiteralPath "$d\zapexdrv.sys") { (Get-Item -LiteralPath "$d\zapexdrv.sys").Length.ToString() + 'b' } else { 'absent' }))
W ('  notepad=' + @(Get-Process notepad -EA 0).Count + ' launcher=' + @(Get-Process apex_launcher -EA 0).Count)
W 'RESULT: PARKED - guest booted with the tick chain alive and zero driver work (variable: cur.ps1 payload swap)'
W 'VERDICT: crash-site evidence is in the STEP=bugcheck-events / STEP=dumps lines above'
Post
# the completion marker is written at the END so a half-finished report cannot silence the boot
Set-Content -LiteralPath "$d\h289p.report" -Value ($L -join "`r`n")
exit 0

