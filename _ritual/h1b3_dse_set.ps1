# h1b3 - put DSE back to 6 (the h1b2 read left it at 0, because bare `-dse` writes 0).
$o = Join-Path $PSScriptRoot '_h1b3.txt'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){ Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"')); exit }
& cmd.exe /c ('"C:\p37vm\payload\kdu.exe" -prv 22 -dse 6 > "' + $o + '" 2>&1')
('rc=' + $LASTEXITCODE) | Add-Content -LiteralPath $o
Select-String -LiteralPath $o -Pattern 'DSE|verification|Return value' | ForEach-Object { $_.Line.Trim() }
