# ============================================================================
# _ritual\qk1_game.ps1 - PLAN stage 1 GATE: the read bridge against the live game.
#
# Read-only: no write, no service change, nothing to restore (R4 by construction).
# Preconditions: (1) Apex is running (the firing range is enough),
#                (2) apexdrv is STARTED  (sc query ApexDrv -> STATE 4 RUNNING).
# The probe auto-detects r5apex_dx12.exe (falls back to r5apex.exe).
#
# Writes _ritual\qk_probe_game_<stamp>.txt and prints its last 6 lines.
# A new file every run (R5) - never overwrite evidence.
# ============================================================================
$ErrorActionPreference = 'Stop'

$root  = Split-Path -Parent $PSScriptRoot
$exe   = Join-Path $root 'QwenKernPremium\build\qk_probe.exe'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out   = Join-Path $PSScriptRoot ("qk_probe_game_$stamp.txt")

if (-not (Test-Path -LiteralPath $exe)) { throw "qk_probe.exe missing: $exe (run tools\BuildQkProbe.ps1)" }

$svc = & sc.exe query ApexDrv 2>&1 | Out-String
if ($svc -notmatch 'STATE\s+:\s+4\s+RUNNING') {
    Write-Host "WARNING: apexdrv is not RUNNING - the probe will report driver-unavailable"
}

$game = Get-Process r5apex_dx12, r5apex -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $game) { Write-Host "WARNING: no r5apex process - the probe will report target-absent" }
else            { Write-Host ("game pid " + $game.Id + " (" + $game.ProcessName + ")") }

& $exe --secs=60 --hz=1 ("--out=" + $out)
$rc = $LASTEXITCODE

Write-Host ""
Write-Host "----- $out -----"
Get-Content -LiteralPath $out -Tail 6
Write-Host "rc=$rc  (0 PASS / 3 target-absent / 5 target died / 7 partial)"
exit $rc
