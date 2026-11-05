# p57_probe.ps1 -- elevated 3-line read probe of one PA; error text to a file.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    Start-Process powershell -Verb RunAs -ArgumentList ('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    exit 0
}
python ext\p58_touchmap.py temp\p58_touchmap.txt 8192 2>&1 | Out-File temp\p58_touchmap_err.txt
