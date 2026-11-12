# ============================================================================
# _ritual\ov60_cycle.ps1 - kill every r5apex_dx12 (EAAC kills are slow, retry),
# wait until none is left, then launch the game fresh.  Run DETACHED: inline
# commands get killed when the harness reuses the terminal.
# ============================================================================
$ErrorActionPreference = 'Continue'
$log = "ov60_cycle $(Get-Date -Format 'HH:mm:ss')`r`n"
function W([string] $s) { $script:log += $s + "`r`n"; [IO.File]::WriteAllText('C:\h320x\t337.txt', $script:log) }

# EAAC denies TerminateProcess to unelevated callers ("Access is denied"), so the
# cycle elevates once and stays elevated: the kill works, and the ov60 wrapper
# then starts without a second UAC prompt.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    W 'not elevated -> relaunching self as admin'
    Start-Process powershell -Verb RunAs -ArgumentList (
        '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath)
    exit 0
}
W 'elevated'

for ($round = 1; $round -le 6; $round++) {
    $p = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue)
    if ($p.Count -eq 0) { break }
    foreach ($x in $p) {
        $r = (taskkill /F /T /PID $x.Id 2>&1) -join ' '
        W "round $round pid=$($x.Id) -> $r"
    }
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if (-not (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue)) { break }
    }
}
$left = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue).Count
W "left=$left"
if ($left -ne 0) { W 'RESULT: FAIL game-will-not-die'; exit 1 }

Start-Sleep -Seconds 2
# watcher first, so it is polling before the process exists
$ov = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\ov60_ingame.ps1'
Start-Process powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $ov) `
    -RedirectStandardOutput C:\h320x\t324_out.txt -RedirectStandardError C:\h320x\t324_err.txt -WindowStyle Hidden
W 'watcher started'
Start-Sleep -Seconds 2
Start-Process -FilePath 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe' -WorkingDirectory 'C:\Program Files\EA Games\Apex'
W "RESULT: launched $(Get-Date -Format 'HH:mm:ss')"
