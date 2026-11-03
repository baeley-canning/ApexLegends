# h1a - set the kdu blocklist bypass live (guest-proven recipe) and prove kdu reads it as disabled.
# Value is missing on this host after the reboot, and h1's pre-flight requires it to be 0.
$o = Join-Path $PSScriptRoot '_h1a.txt'
function W($t){ $t | Add-Content -LiteralPath $o }
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if(-not $adm){ Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"')); exit }
$key = 'HKLM\SYSTEM\CurrentControlSet\Control\CI\Config'
W ('=== h1a ' + (Get-Date -f 'HH:mm:ss') + ' ===')
& reg.exe add $key /v VulnerableDriverBlocklistEnable /t REG_DWORD /d 0 /f 2>&1 | ForEach-Object { W ('  ' + $_) }
W ('  readback=' + (Get-ItemProperty -LiteralPath ('Registry::' + $key)).VulnerableDriverBlocklistEnable)
& cmd.exe /c ('"C:\p37vm\payload\kdu.exe" -list > "' + $PSScriptRoot + '\_h1a_klist.txt" 2>&1')
W ('  kdu -list rc=' + $LASTEXITCODE)
$k = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot '_h1a_klist.txt') -EA SilentlyContinue | Select-Object -First 8)
W ('  ' + ($k -join "`n  "))
W '=== end h1a ==='
