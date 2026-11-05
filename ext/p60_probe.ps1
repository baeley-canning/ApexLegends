# p60_probe.ps1 -- live hunt for the local player name string inside r5apex_dx12.
# ASCII pass first (engine C strings), then UTF-16LE pass (UI text), same band.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    Start-Process powershell -Verb RunAs -ArgumentList ('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    exit 0
}
$needle = 'kern30120'
python ext\p56_hits.py --needle=$needle --lo=0x400000000 --hi=0x780000000 --max_s=90 --out=temp\p60_name_ascii.txt 2>&1 | Out-File temp\p60_name_ascii_err.txt
python ext\p56_hits.py --needle=$needle --lo=0x400000000 --hi=0x780000000 --max_s=90 --utf16 --out=temp\p60_name_u16.txt 2>&1 | Out-File temp\p60_name_u16_err.txt
'P60DONE' | Out-File temp\p60_done.txt
