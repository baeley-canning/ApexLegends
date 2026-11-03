# _p37_ping_task2.ps1 - same proven pattern as p37_task.ps1, pointed at
# _p37_ping.ps1 (task QwenKern_ping2, 10 min limit).
$log = Join-Path $PSScriptRoot '_p37_ping_task.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"') -Verb RunAs -Wait
    exit 0
}
$f = Join-Path $PSScriptRoot '_p37_ping.ps1'
$msg = @()
try {
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $f + '"')
    $p = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName 'QwenKern_ping2' -Action $a -Principal $p -Settings $s -Force -EA Stop | Out-Null
    $msg += ('registered as SYSTEM, target=' + $f)
    Start-ScheduledTask -TaskName 'QwenKern_ping2'
    Start-Sleep -Seconds 5
    $msg += ('state after start=' + (Get-ScheduledTask -TaskName 'QwenKern_ping2').State)
} catch { $msg += ('FAILED: ' + $_.Exception.Message) }
(($msg -join "`r`n")) | Set-Content -LiteralPath $log -Encoding UTF8
