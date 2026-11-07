# ============================================================================
# _ritual\qk1b_gate.ps1 - PLAN STAGE 1b GATE: does a ZERO-ATTACH read survive?
#
# Why: apexdrv reads do one KeStackAttachProcess per IOCTL and EAAC killed the
# game twice on 07/11 shortly after read bursts (ExitType 0x322327458D1ED790).
# gdrv3 has swept 9 GB physical with zero Javelin events. qk_va reproduces that
# safe shape: gdrv3 physical reads + our own page-table walk, no attach.
#
# This script is the whole verdict, no manual interpretation:
#   1. record t0;
#   2. run qk_va --watch=<secs>  (1 Hz reads of the image base; it self-elevates)
#   3. read the Application log for 'EA Javelin Anticheat' events since t0;
#   4. PASS only if the read window was clean AND no Javelin event exists.
#
# Preconditions: Apex running, gdrv3 running (sc query gdrv3 -> STATE 4).
# First run per game session pays ~70-80 s of DTB discovery; it is cached after.
#
# Usage: powershell -ExecutionPolicy Bypass -File _ritual\qk1b_gate.ps1 [-secs 600]
# ============================================================================
[CmdletBinding()]
param([int] $secs = 600)

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out   = Join-Path $root ("temp\qk_va_watch_$stamp.txt")

$game = Get-Process r5apex_dx12, r5apex -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $game) { Write-Host "NO GAME - launch Apex first"; exit 3 }
Write-Host ("game pid " + $game.Id + " (" + $game.ProcessName + ")")

$svc = & sc.exe query gdrv3 2>&1 | Out-String
if ($svc -notmatch 'STATE\s+:\s+4\s+RUNNING') { Write-Host "WARNING: gdrv3 is not RUNNING" }

Write-Host ("window starts now, " + $secs + " s.  evidence -> " + $out)
$t0 = Get-Date

& python (Join-Path $root 'ext\qk_va.py') ("--watch=" + $secs) ("--out=" + $out)
$rc = $LASTEXITCODE

$t1 = Get-Date
Write-Host ""
Write-Host "----- tail of $out -----"
if (Test-Path -LiteralPath $out) { Get-Content -LiteralPath $out -Tail 8 }

$ev = @(Get-WinEvent -FilterHashtable @{LogName = 'Application'
                                        ProviderName = 'EA Javelin Anticheat'
                                        StartTime = $t0} -ErrorAction SilentlyContinue)
Write-Host ""
Write-Host ("Javelin events in the window: " + $ev.Count)
foreach ($e in $ev) { Write-Host ("  " + $e.TimeCreated + "  " + (($e.Message -split "`n")[0])) }

Write-Host ""
if ($rc -eq 0 -and $ev.Count -eq 0) {
    Write-Host "VERDICT: PASS - zero-attach reads for $(([int]($t1 - $t0).TotalSeconds)) s, target alive, no Javelin event"
    exit 0
}
if ($ev.Count -gt 0) {
    Write-Host "VERDICT: FAIL - EAAC still terminates the game during zero-attach reads (the attach was NOT the only trigger)"
    exit 1
}
Write-Host "VERDICT: PARTIAL - reads completed but the probe itself failed (rc=$rc)"
exit 2
