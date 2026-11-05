# p64_win.ps1 -- elevate once and dump the neighbourhood of the candidate bases.
# Usage: powershell -File ext\p64_win.ps1 0x6c6af0864 [--lo=0x40] [--n=0x80]
# Read-only; the output file is new per run (R3/R5), nothing is written to kernel state.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$rid = Get-Date -f 'yyyyMMdd_HHmmss'
$out = "temp\p64_win_$rid.txt"
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    $al = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") + $args
    Start-Process powershell -Verb RunAs -ArgumentList $al
    exit 0
}
"RID=$rid TS=$(Get-Date -f 'HH:mm:ss') GAME=" + @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue).Count |
    Out-File $out
python ext\p64_win.py @args *>&1 | Tee-Object $out -Append
$rc = $LASTEXITCODE
"rc=$rc out=$out"
exit $rc