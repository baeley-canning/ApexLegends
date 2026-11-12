# ============================================================================
# _ritual\ov69_launch.ps1 - start Apex through EA's own chain and wait for a
# window, so ov69_attach.ps1 has a live target.
#
# Why not CreateProcess r5apex_dx12.exe: ov67/ov68 proved every direct spawn
# dies with 0x186AA inside 0.5 s; only the process EA's infra spawns survives.
# So this starts EA Desktop (if needed) and fires the Apex launch deep link.
# Nothing is injected here and no state is mutated - it only starts a game the
# user could start by hand (R1: host-only work).
# Writes: _ritual\ov69_launch.txt
# ============================================================================
param([int] $WaitSec = 300)

$ErrorActionPreference = 'Stop'
$out  = Join-Path $PSScriptRoot 'ov69_launch.txt'
$utf8 = [Text.UTF8Encoding]::new($false)
$log  = @("ov69 launch - " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
function W([string] $s) { $script:log += $s; Write-Host $s }

$game = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Select-Object -First 1
if ($game -and $game.MainWindowHandle -ne 0) {
    W ("already running: pid=$($game.Id) hwnd=$($game.MainWindowHandle) title='$($game.MainWindowTitle)'")
    [IO.File]::WriteAllLines($out, $log, $utf8)
    exit 0
}

$eaApp = 'C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe'
if (-not (Get-Process EADesktop -ErrorAction SilentlyContinue)) {
    if (Test-Path -LiteralPath $eaApp) {
        W "starting EA Desktop"
        Start-Process -FilePath $eaApp
        Start-Sleep -Seconds 25
    } else { W "EA Desktop exe NOT found at $eaApp" }
} else { W 'EA Desktop already running' }

# Apex Legends offer id for the EA app deep link.
$link = 'origin2://game/launch?offerIds=Origin.OFR.50.0000557'
W "launch link: $link"
try { Start-Process $link } catch { W ("deep link failed: " + $_.Exception.Message) }

$deadline = (Get-Date).AddSeconds($WaitSec)
$game = $null
while ((Get-Date) -lt $deadline) {
    $cand = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($cand) {
        Start-Sleep -Seconds 2
        if ((Get-Process -Id $cand.Id -ErrorAction SilentlyContinue)) {
            if ($cand.MainWindowHandle -ne 0) { $game = $cand; break }
        }
    }
    Start-Sleep -Seconds 2
}
if (-not $game) {
    $any = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue)
    W ("no window after ${WaitSec}s; processes=" + (($any | ForEach-Object { $_.Id }) -join ','))
    [IO.File]::WriteAllLines($out, $log, $utf8)
    exit 1
}
W ("game: pid=$($game.Id) hwnd=$($game.MainWindowHandle) title='$($game.MainWindowTitle)' started=$($game.StartTime)")
[IO.File]::WriteAllLines($out, $log, $utf8)
W 'ov69_launch DONE'
