# ============================================================================
# _ritual\ov57_ingame.ps1 - IN-GAME render test (R5: new number, one variable).
#
# Variable vs ov56: the proven offline path is now the *hook* path in
# r5apex_dx12.exe.  ov54/ov55/ov56 only ever called Render() from a test window;
# this is the first run where the queue arrives from the ExecuteCommandLists
# hook inside the game process, i.e. the real Present hook.
#
# In game the first frames are necessarily queue-less (the chain never exposes
# its queue), so this run proves the hold+switch path under a real game:
#   hold -> ExecuteCommandLists captures the queue -> switch -> draw.
#
# Pre-registered PASS (all of it, no partial credit):
#   * `ID3D12CommandQueue::ExecuteCommandLists hook installed`
#   * `captured game command queue`
#   * `overlay ready (... queue=game)`           (private = hold timed out)
#   * `present counter >= 600`                   (>= ~5 s of live render loop)
#   * no `[-] d3d12:` error line and no non-zero removedReason
#   * game process still alive at the end
#   * OCR of the desktop shot contains menu text after INSERT
#
# The game must be started BY THE USER (EA app + EAAC is login bound).  Nothing
# here touches kernel state: usermode injection only, hooks die with the process.
# Evidence: ov57_run.out, ov57_desk_1.png, ov57_ocr_1.txt, payload log copy.
# ============================================================================
param([int] $WaitSec = 480, [int] $PreSec = 20, [int] $GraceSec = 30)

$ErrorActionPreference = 'Stop'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$rit  = Join-Path $root '_ritual'
$qkp  = Join-Path $root 'QwenKernPremium'
$exe  = Join-Path $qkp 'build\apex_launcher.exe'
$dll  = Join-Path $qkp 'build\apexcheat.dll'
$utf8 = [Text.UTF8Encoding]::new($false)
$out  = "ov57 - IN GAME render via the real Present hook - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"

function W([string] $s) { $script:out += $s + "`r`n"; Write-Host $s }
function Finish([string] $verdict, [int] $code) {
    W ''
    W "RESULT: $verdict"
    [IO.File]::WriteAllText((Join-Path $rit 'ov57_run.out'), $script:out, $utf8)
    Write-Host "ov57 DONE $verdict"
    exit $code
}

if (-not (Test-Path $exe)) { throw "launcher missing: $exe" }
if (-not (Test-Path $dll)) { throw "payload missing: $dll" }
W "launcher: $exe"
W "payload : $dll ($((Get-Item $dll).Length) bytes, $((Get-Item $dll).LastWriteTime))"

# ---- 1: the game ------------------------------------------------------------
$deadline = (Get-Date).AddSeconds($WaitSec)
$game = $null
while ((Get-Date) -lt $deadline) {
    $game = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($game) { break }
    Start-Sleep -Seconds 2
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
W "window  : hwnd=$hwnd title='$((Get-Process -Id $game.Id -EA 0).MainWindowTitle)'"
if (-not $hwnd) { Finish 'FAIL no-window' 1 }

$logPath = Join-Path $env:LOCALAPPDATA "QwenKern\payload_$($game.Id).log"
if (Test-Path $logPath) { Remove-Item -LiteralPath $logPath -Force }

# ---- 2: inject --------------------------------------------------------------
# The game needs a moment past the intro before the ladder is worth trying, and
# the launcher needs --inject: without it the console tool prints its menu and
# waits for a keypress instead of injecting (ov57 first attempt, pid 23448).
Start-Sleep -Seconds $PreSec

$launcherOut = Join-Path $rit 'ov57_launcher.out'
$proc = Start-Process -FilePath $exe `
    -ArgumentList @('--inject', "--pid=$($game.Id)", '--timeout=60') `
    -RedirectStandardOutput $launcherOut `
    -RedirectStandardError (Join-Path $rit 'ov57_launcher.err') `
    -PassThru -WindowStyle Hidden
W "launch  : apex_launcher pid=$($proc.Id) (--inject --pid, ladder + sticky as shipped)"

# ---- 3: wait for the payload log -------------------------------------------
$lDeadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $lDeadline -and -not (Test-Path $logPath)) {
    Start-Sleep -Milliseconds 500
    if (-not (Get-Process -Id $game.Id -EA 0)) { break }
}
if (-not (Test-Path $logPath)) {
    # the launcher keeps its redirected stdout open, so read a copy instead
    $copy = Join-Path $rit 'ov57_launcher_copy.txt'
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
    -Pid $game.Id -Out (Join-Path $rit 'ov57_key.txt')) -join "`r`n"
W "INSERT  : $keyTxt"
Start-Sleep -Seconds 3

$alive = [bool](Get-Process -Id $game.Id -EA 0)
$shot  = Join-Path $rit 'ov57_desk_1.png'
(& powershell -ExecutionPolicy Bypass -File (Join-Path $rit 'shot_desk.ps1')) | Out-Null
Copy-Item -LiteralPath (Join-Path $rit 'shot_desk.png') -Destination $shot -Force
$ocrTxt = (& powershell -ExecutionPolicy Bypass -File (Join-Path $rit 'ocr.ps1') `
    -Path $shot -Out (Join-Path $rit 'ov57_ocr_1.txt')) -join "`r`n"
W "ocr     : $ocrTxt"
W '---- ocr text ----'
W ([IO.File]::ReadAllText((Join-Path $rit 'ov57_ocr_1.txt')))

# ---- 5: let it run, then read the log --------------------------------------
Start-Sleep -Seconds 20
$aliveEnd = [bool](Get-Process -Id $game.Id -EA 0)

$logTxt = [IO.File]::ReadAllText($logPath)
Copy-Item -LiteralPath $logPath `
    -Destination (Join-Path $rit "ov57_payload_$($game.Id).log") -Force
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
$ocrTxtAll = [IO.File]::ReadAllText((Join-Path $rit 'ov57_ocr_1.txt'))
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
