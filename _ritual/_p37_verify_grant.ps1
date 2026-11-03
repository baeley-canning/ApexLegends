# _p37_verify_grant.ps1 - did the LSA grant actually land, and does a rebuilt
# SYSTEM token carry it?  (Task Scheduler may serve a cached SYSTEM token.)
$log = Join-Path $PSScriptRoot '_p37_grant_verify.txt'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"') -Verb RunAs -Wait
    exit 0
}
Set-Content -LiteralPath $log -Value ('verify run ' + (Get-Date -f 'HH:mm:ss')) -Encoding UTF8
$inf = Join-Path $env:TEMP 'p37_ur.inf'
& secedit /export /cfg $inf /areas USER_RIGHTS | Out-Null
Add-Content -LiteralPath $log -Value ('policy: ' + ((Select-String -LiteralPath $inf -Pattern 'SeLockMemoryPrivilege' -EA 0 | ForEach-Object { $_.Line.Trim() }) -join ' ; '))
Remove-Item -LiteralPath $inf -EA 0
Restart-Service Schedule -Force
Add-Content -LiteralPath $log -Value ('sched restarted=' + (Get-Service Schedule).Status)
for ($i = 0; $i -lt 24; $i++) { if ((Get-ScheduledTask -TaskName 'QwenKern_p36').State -ne 'Running') { break } ; Start-Sleep -Milliseconds 500 }
Remove-Item -LiteralPath (Join-Path $PSScriptRoot 'p36_write.txt') -EA 0
Remove-Item -LiteralPath (Join-Path $PSScriptRoot '_p36_stderr.txt') -EA 0
Start-ScheduledTask -TaskName 'QwenKern_p36'
Add-Content -LiteralPath $log -Value ('started state=' + (Get-ScheduledTask -TaskName 'QwenKern_p36').State)
