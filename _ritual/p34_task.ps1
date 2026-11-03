# p34_task.ps1 - register + start the p34 matrix as a scheduled task at HIGHEST privileges.
#
# Why: the tool console that launches a probe can be torn down between commands, which kills any
# child process (that is how the first p34 run died at TA t+70s). A scheduled task is owned by the
# Task Scheduler service, so the run survives everything, and -RunLevel Highest means p34 runs
# elevated without a second UAC prompt.
#
# Throwaway helper - this one itself needs ONE UAC approval (registration at Highest needs admin).
$f   = Join-Path $PSScriptRoot 'p34_matrix.ps1'
$log = Join-Path $PSScriptRoot '_p34_task.log'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
"$(Get-Date -f 'dd/MM/yyyy HH:mm:ss') register-run admin=$adm target=$f" | Set-Content -LiteralPath $log
try {
  $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $f + '"')
  $p = New-ScheduledTaskPrincipal -UserId ($env:USERDOMAIN + '\' + $env:USERNAME) -LogonType Interactive -RunLevel Highest
  $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName 'QwenKern_p34' -Action $a -Principal $p -Settings $s -Force | Out-Null
  Start-ScheduledTask -TaskName 'QwenKern_p34'
  Start-Sleep -Seconds 3
  ('started, state=' + (Get-ScheduledTask -TaskName 'QwenKern_p34').State) | Add-Content -LiteralPath $log
} catch {
  ('FAILED: ' + $_.Exception.Message) | Add-Content -LiteralPath $log
}
Get-Content -LiteralPath $log
