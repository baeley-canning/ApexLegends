# p37_task.ps1 - register + start p37_write.ps1 as a scheduled task.
#
# SYSTEM principal, not the interactive user: the W1 lesson stands (the
# interactive elevated token lacks SeLockMemoryPrivilege) and system session 0
# is also immune to a tool-console teardown.  No triggers - this is a one-shot;
# it is Started right here.  2 h limit for a whole-RAM scan.
#
# Self-elevates once (UAC) when registration needs it, and logs to
# _p37_task.log so the state after start is verifiable.
$log = Join-Path $PSScriptRoot '_p37_task.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"') -Verb RunAs -Wait
    exit 0
}
$f = Join-Path $PSScriptRoot 'p37_write.ps1'
$msg = @()
try {
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $f + '"')
    $p = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName 'QwenKern_p37' -Action $a -Principal $p -Settings $s -Force -EA Stop | Out-Null
    $msg += ('registered as SYSTEM, limit=PT2H, target=' + $f)
    Start-ScheduledTask -TaskName 'QwenKern_p37'
    Start-Sleep -Seconds 5
    $msg += ('state after start=' + (Get-ScheduledTask -TaskName 'QwenKern_p37').State)
    $msg += ('lastRun=' + (Get-ScheduledTaskInfo -TaskName 'QwenKern_p37').LastRunTime)
} catch { $msg += ('FAILED: ' + $_.Exception.Message) }
(($msg -join "`r`n")) | Set-Content -LiteralPath $log -Encoding UTF8
Get-Content -LiteralPath $log -Tail 10
