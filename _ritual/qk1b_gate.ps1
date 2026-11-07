# ============================================================================
# _ritual\qk1b_gate.ps1 - PLAN STAGE 1b GATE: does a ZERO-ATTACH read survive?
#
# apexdrv reads do one KeStackAttachProcess per IOCTL and EAAC killed the game
# twice on 07/11 shortly after read bursts (ExitType 0x322327458D1ED790).
# gdrv3 has swept 9 GB physical with zero Javelin events; qk_va reproduces that
# shape (gdrv3 physical reads + our own page walk, no attach).
#
# The script is the whole verdict:
#   1. elevate ONCE at the start (UAC), so nothing pops mid-run;
#   2. record t0;
#   3. run qk_va --watch=<secs> --no-elevate (1 Hz reads; log is live/tailable);
#   4. query the Application log for 'EA Javelin Anticheat' since t0;
#   5. PASS only if the window was clean AND no Javelin event exists.
#
# Preconditions: Apex running, gdrv3 running (sc query gdrv3 -> STATE 4).
# First run per game session pays ~70-80 s of DTB discovery (then cached).
#
# Usage: powershell -ExecutionPolicy Bypass -File _ritual\qk1b_gate.ps1 [-Secs 600]
# ============================================================================
[CmdletBinding()]
param([int] $Secs = 600, [string] $OutFile = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutFile) {
    $OutFile = Join-Path $root ("temp\qk_va_watch_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".txt")
}

$isAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    # -Verb RunAs does NOT quote -ArgumentList elements containing a space, so the
    # repo path ('New User') must be pre-quoted here.
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'),
                 '-Secs', "$Secs", '-OutFile', ('"' + $OutFile + '"'))
    Write-Host "elevating (one UAC prompt) ..."
    $p = Start-Process powershell -ArgumentList $argList -Verb RunAs -PassThru -Wait
    exit $p.ExitCode
}

# ---- elevated half -------------------------------------------------------
$game = Get-Process r5apex_dx12, r5apex -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $game) { Write-Host 'NO GAME - launch Apex first'; exit 3 }
Write-Host ("game pid " + $game.Id + " (" + $game.ProcessName + ")")

$svc = & sc.exe query gdrv3 2>&1 | Out-String
if ($svc -notmatch 'STATE\s+:\s+4\s+RUNNING') { Write-Host 'WARNING: gdrv3 is not RUNNING' }

$script = Join-Path $root 'ext\qk_va.py'

# Resolve the interpreter explicitly: in a ShellExecute-elevated child 'python'
# did not resolve (measured: no python process, no log, wrapper returned 1).
$py = (Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $py) { $py = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe' }
if (-not (Test-Path -LiteralPath $py)) { Write-Host "python.exe not found"; exit 4 }
Write-Host ("python: " + $py)

Write-Host ("window " + $Secs + " s; evidence -> " + $OutFile)
Write-Host 'first run in a game session spends ~80 s resolving the page tables.'

$t0 = Get-Date
Write-Host 'first: resolve the map and read the PE through the driver (zero attach)'
& $py $script ('--pid=' + $game.Id) '--pe' ('--out=' + ($OutFile -replace '\.txt$', '_pe.txt')) '--no-elevate'
Write-Host ''
Write-Host "----- $Secs s watch -----"
& $py $script ('--watch=' + $Secs) ('--out=' + $OutFile) '--no-elevate'
$rc = $LASTEXITCODE
$t1 = Get-Date

Write-Host ''
Write-Host "----- tail of $OutFile -----"
if (Test-Path -LiteralPath $OutFile) { Get-Content -LiteralPath $OutFile -Tail 10 }

$ev = @(Get-WinEvent -FilterHashtable @{LogName = 'Application'
                                        ProviderName = 'EA Javelin Anticheat'
                                        StartTime = $t0} -ErrorAction SilentlyContinue)
Write-Host ''
Write-Host ("Javelin events in the window: " + $ev.Count)
foreach ($e in $ev) { Write-Host ("  " + $e.TimeCreated + "  " + (($e.Message -split "`n")[0])) }

$el = [int]($t1 - $t0).TotalSeconds
Write-Host ''
if ($rc -eq 0 -and $ev.Count -eq 0) {
    Write-Host "VERDICT: PASS - zero-attach reads for $el s, target alive, no Javelin event"
    exit 0
}
if ($ev.Count -gt 0) {
    Write-Host "VERDICT: FAIL - EAAC still terminates the game during zero-attach reads (in $el s)"
    exit 1
}
Write-Host "VERDICT: PARTIAL - reads finished but the probe failed (rc=$rc) - see the log above"
exit 2
