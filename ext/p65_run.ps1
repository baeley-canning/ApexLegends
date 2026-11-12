# p65_run.ps1 -- elevate once and run the health-pair probe (p64_pairs.py) with the
# live seed + chain cue.  Own rid, own output files, pre/post state on disk.
# Usage: powershell -File ext\p65_run.ps1 [extra p64 args...]
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$rid = Get-Date -f 'yyyyMMdd_HHmmss'
$run = "temp\p65_run_$rid.txt"
$out = "temp\p65_$rid.txt"
Set-Content -LiteralPath 'temp\p65_last_run.txt' -Value $rid
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
& $state 'pre' | Out-File "temp\p65_state_$rid.txt"
if (-not @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue).Count) {
    'NOGAME' | Out-File $run
    & $state 'post' | Out-File "temp\p65_state_$rid.txt" -Append
    "rid=$rid run=$run"; exit 4
}
$pyArgs = @($args)
if (-not @($args | Where-Object { $_ -like '--out=*' }).Count) { $pyArgs += "--out=$out" }
if (-not @($args | Where-Object { $_ -like '--seed=*' }).Count) { $pyArgs += '--seed=' }   # default OFF: post-reboot addresses are stale (174154 FATAL); pass --seed=temp\p64_seed18.txt only inside a session
if (-not @($args | Where-Object { $_ -like '--seed-out=*' }).Count) { $pyArgs += '--seed-out=temp\p64_seed20.txt' }
if (-not @($args | Where-Object { $_ -like '--nade2=*' }).Count) { $pyArgs += '--nade2=6' }
if (-not @($args | Where-Object { $_ -like '--shots=*' }).Count) { $pyArgs += '--shots=40' }
$pyArgs += '--chain'
python ext\p64_pairs.py @pyArgs *>&1 | Tee-Object $run
$rc = $LASTEXITCODE
& $state 'post' | Out-File "temp\p65_state_$rid.txt" -Append
"rid=$rid run=$run out=$out rc=$rc"
exit $rc
