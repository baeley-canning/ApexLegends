# p61_live.ps1 -- elevate once and run the whole anchor->damage->diff sequence.
# Usage: powershell -File ext\p61_live.ps1 --needle=kern30120 [--wait=25] [--pre=3]
# Every run gets its own id: run/out files are never overwritten (STATE.md 17:1x defect).
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$rid = Get-Date -f 'yyyyMMdd_HHmmss'
$run = "temp\p61_run_$rid.txt"
$out = "temp\p61_$rid.txt"
$userOut = @($args | Where-Object { $_ -like '--out=*' }).Count -gt 0
Set-Content -LiteralPath 'temp\p61_last_run.txt' -Value $rid
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    $al = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") + $args
    Start-Process powershell -Verb RunAs -ArgumentList $al
    exit 0
}
$alive = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue).Count
if (-not $alive) { 'NOGAME' | Out-File $run; "rid=$rid run=$run"; exit 4 }
$pyArgs = @($args)
if (-not $userOut) { $pyArgs += "--out=$out" }
python ext\p61_live.py @pyArgs *>&1 | Tee-Object $run
$rc = $LASTEXITCODE
"rid=$rid run=$run out=$(if ($userOut) { 'caller --out' } else { $out }) rc=$rc"
exit $rc
