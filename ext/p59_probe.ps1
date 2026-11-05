# p59_probe.ps1 -- elevate and run the needle scanner over the band that used to
# return 1450, against the live p59_hold allocation.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    Start-Process powershell -Verb RunAs -ArgumentList ('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    exit 0
}
python ext\p56_hits.py --needle=P59NEEDLE-0123456789 --lo=0x400000000 --hi=0x780000000 --max_s=90 --no-split --out=temp\p59_ab_nosplit.txt 2>&1 | Out-File temp\p59_ab_nosplit_err.txt
python ext\p56_hits.py --needle=P59NEEDLE-0123456789 --lo=0x400000000 --hi=0x780000000 --max_s=90 --out=temp\p59_ab_split.txt 2>&1 | Out-File temp\p59_ab_split_err.txt
