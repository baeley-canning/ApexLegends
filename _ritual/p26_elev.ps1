# p26_elev.ps1 -- ONE UAC, BOTH ANSWERS: runs the user-mode player probe AND the driver
# load + kernel-reach probe inside the same elevated session.
# run: powershell -NoProfile -ExecutionPolicy Bypass -File _ritual\p26_elev.ps1
$d = $PSScriptRoot
function T($f) { $p = Join-Path $d $f; if (Test-Path -LiteralPath $p) { '##### ' + $f + ' #####'; Get-Content -LiteralPath $p } }
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ("p26_elev elevated=" + $adm)
& (Join-Path $d 'p26_player_probe.ps1')
Start-Sleep -Seconds 2
& (Join-Path $d 'p26_drv.ps1')
T 'p26_player.txt'
T 'p26_drv.txt'
Write-Host "`n=== p26_elev finished; window closes in 30s ==="
Start-Sleep -Seconds 30
