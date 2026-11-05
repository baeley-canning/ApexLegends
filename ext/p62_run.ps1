# p62_run.ps1 -- elevate once and run the value-drop probe.
# Usage: powershell -File ext\p62_run.ps1 [--centre=0x...] [--win=16] [--wait=15] [--pre=12]
# Own rid per run, own output files, pre/post state on disk (STATE.md rules).
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$rid = Get-Date -f 'yyyyMMdd_HHmmss'
$run = "temp\p62_run_$rid.txt"
$out = "temp\p62_$rid.txt"
Set-Content -LiteralPath 'temp\p62_last_run.txt' -Value $rid
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    $al = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") + $args
    Start-Process powershell -Verb RunAs -ArgumentList $al
    exit 0
}
$state = { param($tag)
    $l = @()
    $l += "TAG=$tag RID=$rid TS=$(Get-Date -f 'HH:mm:ss')"
    $l += 'GAME=' + @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue).Count
    $q = (& sc.exe query gdrv3 | Out-String)
    $l += 'GDRV3=' + ([regex]::Match($q, 'STATE\s+:\s+(\d)')).Groups[1].Value
    $l -join ' '
}
& $state 'pre' | Out-File "temp\p62_state_$rid.txt"
if (-not @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue).Count) {
    'NOGAME' | Out-File $run
    & $state 'post' | Out-File "temp\p62_state_$rid.txt" -Append
    "rid=$rid run=$run"; exit 4
}
$pyArgs = @($args)
if (-not @($args | Where-Object { $_ -like '--out=*' }).Count) { $pyArgs += "--out=$out" }
python ext\p62_drop.py @pyArgs *>&1 | Tee-Object $run
$rc = $LASTEXITCODE
& $state 'post' | Out-File "temp\p62_state_$rid.txt" -Append
"rid=$rid run=$run out=$out rc=$rc"
exit $rc
