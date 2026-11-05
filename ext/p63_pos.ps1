# p63_pos.ps1 -- elevate once, locate the local player struct by walking (no damage needed).
# Usage: powershell -File ext\p63_pos.ps1 --needle=kern30120 [--walk=6]
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    $al = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") + $args
    Start-Process powershell -Verb RunAs -ArgumentList $al
    exit 0
}
$alive = @(Get-Process r5apex_dx12 -ErrorAction SilentlyContinue).Count
if (-not $alive) { 'NOGAME' | Out-File temp\p63_out.txt; exit 4 }
python ext\p63_pos.py @args *>&1 | Tee-Object temp\p63_run.txt
