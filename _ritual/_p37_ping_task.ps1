# _p37_ping_task.ps1 - one-shot SYSTEM launch of _p37_ping.ps1 (self-elevates).
$log = Join-Path $PSScriptRoot '_p37_ping_task.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"') -Verb RunAs -Wait
    exit 0
}
$f = Join-Path $PSScriptRoot '_p37_ping.ps1'
try {
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $f + '"')
    $p = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName 'QwenKern_ping' -Action $a -Principal $p -Settings $s -Force | Out-Null
    Start-ScheduledTask -TaskName 'QwenKern_ping'
    'started' | Set-Content -LiteralPath $log -Encoding UTF8
} catch { ('FAIL ' + $_.Exception.Message) | Set-Content -LiteralPath $log -Encoding UTF8 }
