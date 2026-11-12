# ============================================================================
# _ritual\ov60_ingame.ps1 - IN-GAME render test (R5: new number, one variable).
#
# Variable vs ov57/ov58/ov59: injection TIMING, not method.
#   ov57  unelevated          -> every rung `OpenProcess: 5`
#   ov58  elevated, --method=manual -> `VirtualAllocEx(image): 5`
#   ov59  elevated, full ladder     -> `VirtualAllocEx: 5` on A7/A3/A2/A1, A4
#                                     "module list denied", B3 needs DSE off
#   (ov59_alloc_probe.ps1: OpenProcess succeeds, VirtualAllocEx(RW) = error 5,
#    so the wall is EAAC's allocation jail on the already-running game - today's
#    Apex update hardened it; Elocarry is on "standby for update" as well.)
# So ov60 changes *when*: it injects the moment the process exists (window not
# required) and retries the ladder up to -Attempts times, because the jail only
# arms once the AC's own init has run.  Still usermode-only, no driver/DSE.
#
# The game must be started by an external actor BEFORE this script - it waits for
# r5apex_dx12 to appear.  Everything else (gates, INSERT, shots) unchanged.
# ============================================================================
param([int] $WaitSec = 300, [int] $PreSec = 0, [int] $GraceSec = 30,
      [string] $Method = 'ladder', [int] $Attempts = 3, [int] $GapSec = 25)

$ErrorActionPreference = 'Stop'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$rit  = Join-Path $root '_ritual'
$qkp  = Join-Path $root 'QwenKernPremium'
$exe  = Join-Path $qkp 'build\apex_launcher.exe'
$dll  = Join-Path $qkp 'build\apexcheat.dll'
$utf8 = [Text.UTF8Encoding]::new($false)
$out  = "ov60 - IN GAME render via the real Present hook - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"

function W([string] $s) { $script:out += $s + "`r`n"; Write-Host $s }
function Finish([string] $verdict, [int] $code) {
    W ''
    W "RESULT: $verdict"
    [IO.File]::WriteAllText((Join-Path $rit 'ov60_run.out'), $script:out, $utf8)
    Write-Host "ov60 DONE $verdict"
    exit $code
}

if (-not (Test-Path $exe)) { throw "launcher missing: $exe" }
if (-not (Test-Path $dll)) { throw "payload missing: $dll" }
W "launcher: $exe"
W "payload : $dll ($((Get-Item $dll).Length) bytes, $((Get-Item $dll).LastWriteTime))"

# ---- 1: the game ------------------------------------------------------------
# A second r5apex_dx12.exe can exist briefly (the stub that re-execs and exits).
# Only accept a candidate that survives two 2 s ticks, otherwise ov60 would aim
# at a dead pid and, worse, at that pid's *stale* payload log from a recycled
# pid.  Absence of *any* process between the stub's exit and the real spawn is
# normal and must not abort the wait (ov60 attempt 2 did exactly that).
$deadline = (Get-Date).AddSeconds($WaitSec)
$game = $null
while ((Get-Date) -lt $deadline -and -not $game) {
    $cand = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Select-Object -First 1
    if (-not $cand) { Start-Sleep -Seconds 2; continue }
    Start-Sleep -Seconds 1
    if (-not (Get-Process -Id $cand.Id -ErrorAction SilentlyContinue)) { continue }
    Start-Sleep -Seconds 1
    if (Get-Process -Id $cand.Id -ErrorAction SilentlyContinue) { $game = $cand }
}
if (-not $game) { Finish 'FAIL no-game (start Apex first)' 1 }
W "game    : pid=$($game.Id) started=$($game.StartTime)"

# Wait for a real window - before that the render thread has not started and a
# timeout would say nothing about the overlay.
$wDeadline = (Get-Date).AddSeconds(180)
while ((Get-Date) -lt $wDeadline -and (Get-Process -Id $game.Id -EA 0).MainWindowHandle -eq 0) {
    Start-Sleep -Seconds 2
}
$hwnd = (Get-Process -Id $game.Id -EA 0).MainWindowHandle
W "window  : hwnd=$hwnd title='$((Get-Process -Id $game.Id -EA 0).MainWindowTitle)' (not required in early mode)"

$logPath = Join-Path $env:LOCALAPPDATA "QwenKern\payload_$($game.Id).log"
if (Test-Path $logPath) { Remove-Item -LiteralPath $logPath -Force }
# Purge payload logs whose pid is no longer alive: a recycled pid must never make
# a stale file look like a successful injection (ov60 attempt 1 did exactly that).
$logDir = Join-Path $env:LOCALAPPDATA 'QwenKern'
Get-ChildItem $logDir -Filter 'payload_*.log' -ErrorAction SilentlyContinue | ForEach-Object {
    $pidPart = [int]($_.BaseName -split '_')[1]
    if (-not (Get-Process -Id $pidPart -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
    }
}
W "log dir : $logDir (stale payload logs purged)"

# ---- 2: inject, early, retrying ----------------------------------------------
Start-Sleep -Seconds $PreSec

$launcherOut = 'C:\h320x\t287_launch.txt'
# -RedirectStandardOutput and -Verb RunAs are mutually exclusive on PS 5.1, so an
# elevated wrapper does the redirection (ov60_launch_elevated.ps1) and appends the
# ladder output to $launcherOut.  Without it the elevated console vanishes.
$wrapper = Join-Path $rit 'ov60_launch_elevated.ps1'
$won = $false
for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    if (-not (Get-Process -Id $game.Id -EA 0)) { W "attempt ${attempt}: game gone"; break }
    $proc = Start-Process powershell -Verb RunAs -PassThru -ArgumentList (
        '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Pid_ {1} -Method {2} -Out "{3}"' -f
        $wrapper, $game.Id, $Method, $launcherOut)
    W "attempt ${attempt}/${Attempts}: ELEVATED wrapper pid=$($proc.Id) --method=$Method"
    $t0a = Get-Date
    $deadlineA = (Get-Date).AddSeconds($GapSec)
    while ((Get-Date) -lt $deadlineA) {
        Start-Sleep -Milliseconds 500
        if (Test-Path $logPath) {
            # fresh = written during this attempt, not a leftover
            if ((Get-Item $logPath).LastWriteTime -gt $t0a) { $won = $true; break }
        }
        if (-not (Get-Process -Id $game.Id -EA 0)) { break }
    }
    if ($won) { break }
}
if (-not $won -and -not (Test-Path $logPath)) {
    # the launcher keeps its redirected stdout open, so read a copy instead
    $copy = Join-Path $rit 'ov60_launcher_copy.txt'
    Copy-Item -LiteralPath $launcherOut -Destination $copy -Force -ErrorAction SilentlyContinue
    W '---- launcher output ----'
    if (Test-Path $copy) { W ([IO.File]::ReadAllText($copy) -replace "`r`n", "`r`n  ") }
    else { W '(launcher output locked / empty)' }
    Finish 'FAIL no-payload-log (injection did not happen)' 1
}
W "log     : $logPath"

# ---- 4: grace, then open the menu and shoot --------------------------------
Start-Sleep -Seconds $GraceSec

$keyTxt = (& powershell -ExecutionPolicy Bypass -File (Join-Path $rit 'h159_insertkey.ps1') `
    -Pid $game.Id -Out (Join-Path $rit 'ov60_key.txt')) -join "`r`n"
W "INSERT  : $keyTxt"
Start-Sleep -Seconds 3

$alive = [bool](Get-Process -Id $game.Id -EA 0)
$shot  = Join-Path $rit 'ov60_desk_1.png'
(& powershell -ExecutionPolicy Bypass -File (Join-Path $rit 'shot_desk.ps1')) | Out-Null
Copy-Item -LiteralPath (Join-Path $rit 'shot_desk.png') -Destination $shot -Force
$ocrTxt = (& powershell -ExecutionPolicy Bypass -File (Join-Path $rit 'ocr.ps1') `
    -Path $shot -Out (Join-Path $rit 'ov60_ocr_1.txt')) -join "`r`n"
W "ocr     : $ocrTxt"
W '---- ocr text ----'
W ([IO.File]::ReadAllText((Join-Path $rit 'ov60_ocr_1.txt')))

# ---- 5: let it run, then read the log --------------------------------------
Start-Sleep -Seconds 20
$aliveEnd = [bool](Get-Process -Id $game.Id -EA 0)

$logTxt = [IO.File]::ReadAllText($logPath)
Copy-Item -LiteralPath $logPath `
    -Destination (Join-Path $rit "ov60_payload_$($game.Id).log") -Force
W '---- payload log ----'
W $logTxt

# ---- 6: verdict -------------------------------------------------------------
$hookInst  = $logTxt -match 'ExecuteCommandLists hook installed'
$queueCap  = $logTxt -match 'captured game command queue'
$readyGame = $logTxt -match 'overlay ready \(.*queue=game'
$readyPriv = $logTxt -match 'overlay ready \(.*queue=private'
$counts    = @([regex]::Matches($logTxt, 'present counter = (\d+)') |
               ForEach-Object { [int]$_.Groups[1].Value })
$maxCount  = if ($counts.Count) { ($counts | Measure-Object -Maximum).Maximum } else { 0 }
$errLines  = @($logTxt -split "`r`n" | Where-Object { $_ -match '\[-\] d3d12:' })
$removedOk = -not ($logTxt -match 'removedReason[^\r\n]*0x(?!00000000)[0-9A-Fa-f]{8}')
$ocrTxtAll = [IO.File]::ReadAllText((Join-Path $rit 'ov60_ocr_1.txt'))
$ocrHit    = $ocrTxtAll -match 'QWENKERN|MENU|ESP'

W ''
W "check hook installed : $hookInst"
W "check queue captured : $queueCap"
W "check ready game     : $readyGame (private=$readyPriv)"
W "check frames         : max present counter = $maxCount (need >= 600)"
W "check errors         : $($errLines.Count) '[-] d3d12:' line(s)"
W "check removedReason  : $removedOk"
W "check game alive     : at-shot=$alive at-end=$aliveEnd"
W "check ocr menu text  : $ocrHit"

$pass = $hookInst -and $queueCap -and $readyGame -and $maxCount -ge 600 -and
        $errLines.Count -eq 0 -and $removedOk -and $aliveEnd -and $ocrHit
Finish $(if ($pass) { 'PASS' } else { 'FAIL' }) $(if ($pass) { 0 } else { 2 })
