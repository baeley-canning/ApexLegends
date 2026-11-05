# p60_snap.ps1 <label> [hitsfile] -- elevate and run p60_snap.py
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    $al = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") + $args
    Start-Process powershell -Verb RunAs -ArgumentList $al
    exit 0
}
python ext\p60_snap.py @args *>&1 | Tee-Object temp\p60_snap_run.txt
