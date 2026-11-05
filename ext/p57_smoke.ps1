# p57_smoke.ps1 -- elevated one-shot: dump evidence for the 18:00 stop, then a
# game-less smoke of the windowed sweep mechanics. Read-only. Self-elevating
# (ritual pattern): a non-admin start relaunches itself via UAC and tails the log.
$log = Join-Path (Split-Path -Parent $PSScriptRoot) 'temp\p57_smoke.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    "relaunching elevated" | Set-Content -LiteralPath $log
    $args = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait
    Get-Content -LiteralPath $log -Tail 30
    exit 0
}
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
"ADMIN ok " + (Get-Date -Format 'HH:mm:ss') | Add-Content -LiteralPath $log
& powershell -NoProfile -File (Join-Path $PSScriptRoot 'p57_dmps.ps1')
python ext\p56_hits.py --needle="New User" --lo=0x10d000000 --hi=0x11b000000 `
    --sig --trace --max_s=30 --out=temp\p57_smoke.txt
"SMOKE_EXIT=$LASTEXITCODE" | Add-Content -LiteralPath $log
