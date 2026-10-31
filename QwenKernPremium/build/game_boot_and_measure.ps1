# ============================================================================
# build\game_boot_and_measure.ps1 — start Apex and measure the NON-elevated
# access picture the moment EAC is armed.  Companion to elevated_phase1.ps1:
# that one produces the elevated half of the same table (Q9), this one the
# non-elevated half, both against a target whose AC stack is definitely up
# (elev_* of 17:19 was captured with the game CLOSED - r5apex_dx12.exe and with
# it the EAC minifilter were gone, so it is a "no-AC" row, not a game row).
# ============================================================================
$ErrorActionPreference = 'Continue'

$root   = 'C:\Users\New User\OneDrive\Desktop\cheating\QwenKernPremium'
$ev     = Join-Path $root 'build\phase1_evidence'
$apexDir = 'C:\Program Files\EA Games\Apex'
$log    = Join-Path $root 'build\game_boot.txt'

"== game boot $(Get-Date -Format 'HH:mm:ss') ==" | Out-File -Encoding utf8 $log
Start-Process (Join-Path $apexDir 'r5apex_dx12.exe') -WorkingDirectory $apexDir

$apex = $null
$eac  = $null
for ($attempt = 0; $attempt -lt 120; ++$attempt) {
    $apex = (Get-Process r5apex_dx12 -ErrorAction SilentlyContinue | Select-Object -First 1).Id
    $eac  = (Get-Process 'EAAntiCheat.GameService' -ErrorAction SilentlyContinue | Select-Object -First 1).Id
    "$(Get-Date -Format 'HH:mm:ss') apex=$apex eac=$eac" |
        Out-File -Encoding utf8 -Append $log
    if ($apex -and $eac) { break }
    Start-Sleep -Seconds 2
}

Set-Location (Join-Path $root 'build')
if (-not $apex) { 'game never started' | Out-File -Encoding utf8 (Join-Path $ev 'nonelev_probe.txt'); exit 2 }

# Give the game a moment to finish bring-up (the AC arming is staged), then
# measure with the SAME command line as the elevated pass so the rows compare.
Start-Sleep -Seconds 10
.\apex_launcher.exe --forget-sticky --probe --pid=$apex *>&1 |
    Out-File -Encoding utf8 (Join-Path $ev 'nonelev_probe.txt')
"PROBE_EXIT=$LASTEXITCODE" | Out-File -Encoding utf8 -Append (Join-Path $ev 'nonelev_probe.txt')

.\apex_launcher.exe --inject --no-wait --pid=$apex *>&1 |
    Out-File -Encoding utf8 (Join-Path $ev 'nonelev_ladder.txt')
"LADDER_EXIT=$LASTEXITCODE" | Out-File -Encoding utf8 -Append (Join-Path $ev 'nonelev_ladder.txt')

$env:APEX_PID = $apex
'READY' | Out-File -Encoding utf8 (Join-Path $ev 'game_ready.txt')
