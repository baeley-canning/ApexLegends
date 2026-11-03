# h2_task.ps1 - register + start h2 as a HIGHEST scheduled task (console teardown cannot kill it).
# Same shape as p34_task.ps1: one UAC for the registration, then the Task Scheduler owns the run.
$f   = Join-Path $PSScriptRoot 'h2_gate.ps1'
$log = Join-Path $PSScriptRoot '_h2_task.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
"$(Get-Date -f 'dd/MM/yyyy HH:mm:ss') register-run admin=$adm target=$f" | Set-Content -LiteralPath $log
if(-not $adm){ Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"')); exit }
try {
  $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $f + '" -WinSec 1800 -BootSec 600')
  $p = New-ScheduledTaskPrincipal -UserId ($env:USERDOMAIN + '\' + $env:USERNAME) -LogonType Interactive -RunLevel Highest
  $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName 'QwenKern_h2' -Action $a -Principal $p -Settings $s -Force | Out-Null
  Start-ScheduledTask -TaskName 'QwenKern_h2'
  Start-Sleep -Seconds 3
  ('started, state=' + (Get-ScheduledTask -TaskName 'QwenKern_h2').State) | Add-Content -LiteralPath $log
} catch {
  ('FAILED: ' + $_.Exception.Message) | Add-Content -LiteralPath $log
}
Get-Content -LiteralPath $log
