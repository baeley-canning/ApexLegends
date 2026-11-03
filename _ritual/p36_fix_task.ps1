# p36_fix_task.ps1 - repoint task QwenKern_p36 at the crash-resilient wrapper.
#   action  : p36_retry.ps1 (END-aware, in-invocation retries, badpa seed/merge)
#   trigger : AtLogOn (PT45S delay) - auto-resume after every bugcheck-driven reboot
#   limit   : PT2H (was PT30M - a full sweep + retries can outgrow 30 min)
#   settings: IgnoreNew (the Global\QwenKern_p36 mutex also guards), StartWhenAvailable
# Self-elevates with ONE UAC prompt, same pattern as p36_task.ps1, then starts
# the task and logs everything to _p36_fix.log for verification.
$log = Join-Path $PSScriptRoot '_p36_fix.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"') -Verb RunAs -Wait
    exit 0
}
$retry = Join-Path $PSScriptRoot 'p36_retry.ps1'
$msg = @()
try {
    $a  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $retry + '"')
    # SYSTEM, not the interactive user: the interactive elevated token does NOT carry
    # SeLockMemoryPrivilege (lithuanian p36 W1 run: NOT_ASSIGNED, 0xC0000022), while
    # LocalSystem's default token has it enabled - that is exactly what W1
    # (\Device\PhysicalMemory) needs.  ServiceAccount = no password, session 0.
    $p  = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $trStart = New-ScheduledTaskTrigger -AtStartup
    $trStart.Delay = 'PT45S'
    $s  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $reg = $null
    try {
        $trLog = New-ScheduledTaskTrigger -AtLogOn -User ($env:USERDOMAIN + '\' + $env:USERNAME)
        $trLog.Delay = 'PT45S'
        $reg = Register-ScheduledTask -TaskName 'QwenKern_p36' -Action $a -Principal $p -Trigger @($trStart, $trLog) -Settings $s -Force -EA Stop
        $msg += 'task re-registered as SYSTEM: triggers=startup/logon (PT45S) limit=PT2H'
    } catch {
        $msg += ('startup+logon combo rejected (' + $_.Exception.Message + '), retrying startup-only')
        $reg = Register-ScheduledTask -TaskName 'QwenKern_p36' -Action $a -Principal $p -Trigger $trStart -Settings $s -Force -EA Stop
        $msg += 'task re-registered as SYSTEM: trigger=startup only (PT45S) limit=PT2H'
    }
    Start-ScheduledTask -TaskName 'QwenKern_p36'
    Start-Sleep -Seconds 5
    $msg += ('state after start=' + (Get-ScheduledTask -TaskName 'QwenKern_p36').State)
    $msg += ('lastRun=' + (Get-ScheduledTaskInfo -TaskName 'QwenKern_p36').LastRunTime)
} catch { $msg += ('FAILED: ' + $_.Exception.Message) }
(($msg -join "`r`n")) | Set-Content -LiteralPath $log -Encoding UTF8