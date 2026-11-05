# arm_task.ps1 -- run elevated; (re)register the cmd.txt listener as a detached SYSTEM-parent task.
# Uses the ScheduledTasks cmdlets so the -File argument keeps its quotes (schtasks /tr strips them).
$repo  = 'C:\Users\New User\OneDrive\Desktop\cheating'
$log   = Join-Path $repo 'temp\arm.log'
$name  = 'cheat_p64_arm'
$ps    = Join-Path $repo 'ext\p64_arm.ps1'
$probe = Join-Path $repo 'temp\arm_probe.txt'
function L([string]$t) { ('{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $t) | Out-File -Append -Encoding utf8 $log }
"=== arm_task $(Get-Date -Format o) ===" | Set-Content -Encoding utf8 $log
L ('elevated=' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

Unregister-ScheduledTask -TaskName $name -Confirm:$false -EA 0
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ps + '"')
$prn = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
# logon trigger: a bugcheck kills this host regularly; the listener must return by itself, not by hand
$trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
try {
    Register-ScheduledTask -TaskName $name -Action $act -Trigger $trg -Principal $prn -Settings $set -Force -EA Stop | Out-Null
    L 'REGISTER ok'
} catch { L ('REGISTER threw: ' + $_.Exception.Message) }
try {
    Start-ScheduledTask -TaskName $name -EA Stop
    L 'START ok'
} catch { L ('START threw: ' + $_.Exception.Message) }
Start-Sleep -Seconds 2
$i = Get-ScheduledTaskInfo -TaskName $name -EA 0
L ('INFO lastRun=' + $i.LastRunTime + ' lastResult=' + $i.LastTaskResult)

Remove-Item -LiteralPath $probe -EA 0
Set-Content -LiteralPath (Join-Path $repo 'temp\cmd.txt') -Encoding Unicode -Value ('"ARM_OK $(Get-Date -Format o)" | Out-File -Encoding ascii temp\arm_probe.txt')
for ($n = 0; $n -lt 20; $n++) {
    Start-Sleep -Milliseconds 500
    if (Test-Path $probe) { break }
}
L ('PROBE ok=' + (Test-Path $probe) + ' waited_ms=' + ($n * 500))
L 'arm_task end'
