# ============================================================================
# _ritual\ov59_ingame.ps1 - IN-GAME render test (R5: new number, one variable).
#
# Variable vs ov57: ov57 ran the launcher NON-elevated and every rung died with
# `OpenProcess failed: 5` (EAAC protects the target from unelevated handles, and
# the launcher cannot even read the module list, so its verdicts are worthless).
# ov59 runs the launcher ELEVATED (one UAC consent) and pins `--method=manual`,
# which keeps the run usermode-only: no `sc create`/driver load, so no kernel
# state changes and no confounding of the render result by the gdrv3 issue.
#
# Everything else - the gates, the INSERT, the shots - is unchanged from ov57.
# ============================================================================
param([int] $WaitSec = 480, [int] $PreSec = 20, [int] $GraceSec = 30,
      [string] $Method = 'ladder')

$ErrorActionPreference = 'Stop'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$rit  = Join-Path $root '_ritual'
$qkp  = Join-Path $root 'QwenKernPremium'
$exe  = Join-Path $qkp 'build\apex_launcher.exe'
$dll  = Join-Path $qkp 'build\apexcheat.dll'
$utf8 = [Text.UTF8Encoding]::new($false)
$out  = "ov59 - IN GAME render via the real Present hook - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"

function W([string] $s) { $script:out += $s + "`r`n"; Write-Host $s }
function Finish([string] $verdict, [int] $code) {
    W ''
    W "RESULT: $verdict"
    [IO.File]::WriteAllText((Join-Path $rit 'ov59_run.out'), $script:out, $utf8)
    Write-Host "ov59 DONE $verdict"
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
# waits for a keypress instead of injecting (earlier in this session: ov57 unelevated, ov58 elevated manual).
Start-Sleep -Seconds $PreSec

$launcherOut = 'C:\h320x\t287_launch.txt'
# -RedirectStandardOutput and -Verb RunAs are mutually exclusive on PS 5.1, so an
# elevated wrapper does the redirection (ov59_launch_elevated.ps1) and writes the
# ladder output to $launcherOut.  Without it the elevated console vanishes.
$wrapper = Join-Path $rit 'ov59_launch_elevated.ps1'
$proc = Start-Process powershell -Verb RunAs -PassThru -ArgumentList (
    '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Pid_ {1} -Method {2} -Out "{3}"' -f
    $wrapper, $game.Id, $Method, $launcherOut)
W "launch  : ELEVATED wrapper pid=$($proc.Id) --method=$Method (UAC to accept)"

# ---- 3: wait for the payload log -------------------------------------------
$lDeadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $lDeadline -and -not (Test-Path $logPath)) {
    Start-Sleep -Milliseconds 500
    if (-not (Get-Process -Id $game.Id -EA 0)) { break }
}
if (-not (Test-Path $logPath)) {
    # the launcher keeps its redirected stdout open, so read a copy instead
    $copy = Join-Path $rit 'ov59_launcher_copy.txt'
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
    -Pid $game.Id -Out (Join-Path $rit 'ov59_key.txt')) -join "`r`n"
W "INSERT  : $keyTxt"
Start-Sleep -Seconds 3

$alive = [bool](Get-Process -Id $game.Id -EA 0)
$shot  = Join-Path $rit 'ov59_desk_1.png'
(& powershell -ExecutionPolicy Bypass -File (Join-Path $rit 'shot_desk.ps1')) | Out-Null
Copy-Item -LiteralPath (Join-Path $rit 'shot_desk.png') -Destination $shot -Force
$ocrTxt = (& powershell -ExecutionPolicy Bypass -File (Join-Path $rit 'ocr.ps1') `
    -Path $shot -Out (Join-Path $rit 'ov59_ocr_1.txt')) -join "`r`n"
W "ocr     : $ocrTxt"
W '---- ocr text ----'
W ([IO.File]::ReadAllText((Join-Path $rit 'ov59_ocr_1.txt')))

# ---- 5: let it run, then read the log --------------------------------------
Start-Sleep -Seconds 20
$aliveEnd = [bool](Get-Process -Id $game.Id -EA 0)

$logTxt = [IO.File]::ReadAllText($logPath)
Copy-Item -LiteralPath $logPath `
    -Destination (Join-Path $rit "ov59_payload_$($game.Id).log") -Force
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
$ocrTxtAll = [IO.File]::ReadAllText((Join-Path $rit 'ov59_ocr_1.txt'))
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
