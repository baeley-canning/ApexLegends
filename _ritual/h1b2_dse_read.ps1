# h1b2 - read-only DSE state re-check (kdu -dse with no value). Loads prv 22, writes nothing.
$o = Join-Path $PSScriptRoot '_h1b2.txt'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){ Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"')); exit }
& cmd.exe /c ('"C:\p37vm\payload\kdu.exe" -prv 22 -dse > "' + $o + '" 2>&1')
('rc=' + $LASTEXITCODE) | Add-Content -LiteralPath $o
Select-String -LiteralPath $o -Pattern 'DSE|flags|verification|Selected|block list' | ForEach-Object { $_.Line.Trim() }
