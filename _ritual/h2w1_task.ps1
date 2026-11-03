# h2w1_task.ps1 - register + start the watch-only gate continuation as a scheduled task so the
# agent's console teardown cannot kill the 1800 s window (proven sampler lesson: only scheduler
# ownership survives). Tries a LIMITED registration first - nothing in the watch needs elevation,
# so the user does not get a UAC dialog on top of the live game. Self-elevates only if the
# registration is denied.
param([switch]$Elevated)
$f   = Join-Path $PSScriptRoot 'h2w1_watch.ps1'
$log = Join-Path $PSScriptRoot '_h2w1_task.log'
$tn  = 'QwenKern_h2w1'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
"$(Get-Date -f 'dd/MM/yyyy HH:mm:ss') register-run admin=$adm elevated=$Elevated target=$f" | Add-Content -LiteralPath $log
try {
  $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $f + '" -WinSec 1800')
  $p = New-ScheduledTaskPrincipal -UserId ($env:USERDOMAIN + '\' + $env:USERNAME) -LogonType Interactive -RunLevel Limited
  $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName $tn -Action $a -Principal $p -Settings $s -Force | Out-Null
  Start-ScheduledTask -TaskName $tn
  Start-Sleep -Seconds 3
  ('started (limited), state=' + (Get-ScheduledTask -TaskName $tn).State) | Add-Content -LiteralPath $log
} catch {
  ('LIMITED registration failed: ' + $_.Exception.Message) | Add-Content -LiteralPath $log
  if(-not $adm -and -not $Elevated){
    ('re-launching elevated') | Add-Content -LiteralPath $log
    Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-Elevated')
    exit
  }
  try {
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $f + '" -WinSec 1800')
    $p = New-ScheduledTaskPrincipal -UserId ($env:USERDOMAIN + '\' + $env:USERNAME) -LogonType Interactive -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $tn -Action $a -Principal $p -Settings $s -Force | Out-Null
    Start-ScheduledTask -TaskName $tn
    Start-Sleep -Seconds 3
    ('started (highest), state=' + (Get-ScheduledTask -TaskName $tn).State) | Add-Content -LiteralPath $log
  } catch { ('HARD FAIL: ' + $_.Exception.Message) | Add-Content -LiteralPath $log }
}
Get-Content -LiteralPath $log -Tail 6
