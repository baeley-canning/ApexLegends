# p38_chk_task.ps1 - register + start p38_chk.ps1 as a scheduled task (SYSTEM).
# One-shot, self-elevating for registration, logs to _p38_chk_task.log.
$log = Join-Path $PSScriptRoot '_p38_chk_task.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"') -Verb RunAs -Wait
    exit 0
}
$f = Join-Path $PSScriptRoot 'p38_chk.ps1'
$msg = @()
try {
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $f + '"')
    $p = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName 'QwenKern_p38chk' -Action $a -Principal $p -Settings $s -Force -EA Stop | Out-Null
    $msg += ('registered as SYSTEM, target=' + $f)
    Start-ScheduledTask -TaskName 'QwenKern_p38chk'
    Start-Sleep -Seconds 3
    $msg += ('state after start=' + (Get-ScheduledTask -TaskName 'QwenKern_p38chk').State)
} catch { $msg += ('FAILED: ' + $_.Exception.Message) }
(($msg -join "`r`n")) | Set-Content -LiteralPath $log -Encoding UTF8
Get-Content -LiteralPath $log -Tail 5
