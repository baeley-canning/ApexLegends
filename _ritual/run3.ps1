# run3.ps1 -- single-UAC-click launcher for the p26 sha256-member probe + re-sign run.
# start elevated:  Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','...\run3.ps1'
$d = $PSScriptRoot
$state = Join-Path $d 'run3.state'
function S([string]$s) { ('{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $s) | Add-Content -LiteralPath $state -Encoding utf8 }
Remove-Item -LiteralPath $state -Force -EA SilentlyContinue
$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
S ('elev=' + $adm + ' pid=' + $PID + ' exe=' + $PSCommandPath)
if (Test-Path -LiteralPath (Join-Path $d 'p26_cat.txt')) {
    Copy-Item -LiteralPath (Join-Path $d 'p26_cat.txt') -Destination (Join-Path $d 'p26_cat_prev.txt') -Force
}
$t0 = Get-Date
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $d 'p26_cat.ps1') -NoSelfElevate *>&1 | ForEach-Object { S ('  | ' + $_) }
S ('p26_cat finished, exit=' + $LASTEXITCODE + ' elapsed=' + [int]((Get-Date) - $t0).TotalSeconds + 's')
S 'END-run3'
