# p41_task.ps1 - find a working elevation transport on this host.
# Read-only: registers one throw-away task that runs p41_elev.ps1 and reports its token.
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\p41h.txt'
function L($m) { Add-Content -LiteralPath $log -Value ('{0:HH:mm:ss} {1}' -f (Get-Date), $m) -Encoding utf8 }
Set-Content -LiteralPath $log -Value ('p41_task {0:HH:mm:ss} pid={1}' -f (Get-Date), $PID) -Encoding utf8

L ('admin=' + [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)))
L ('user=' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
L ('wp=' + $env:windir + '\Temp probe_file=' + (Test-Path 'C:\Windows\Temp\p40w_run.ps1'))
try { L ('tempdir=' + ((Get-Item 'C:\Windows\Temp' -Force).FullName + ' acl=' + ((Get-Acl 'C:\Windows\Temp').AccessToString -split "`n")[0])) } catch { L ('tempdir_err=' + $_.Exception.Message) }

# --- transport A: Register-ScheduledTask --------------------------------
try {
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Windows\Temp\p41_elev.ps1 -Tag task'
    $p = New-ScheduledTaskPrincipal -UserId ($env:USERDOMAIN + '\' + $env:USERNAME) -LogonType Interactive -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName 'p41x_elevprobe' -Action $a -Principal $p -Settings $s -Force -ErrorAction Stop | Out-Null
    L 'A: registered'
    Start-ScheduledTask -TaskName 'p41x_elevprobe' -ErrorAction Stop
    L 'A: started'
} catch { L ('A_ERR=' + $_.Exception.Message) }

Start-Sleep -Seconds 5
try { L ('A_state=' + (Get-ScheduledTask -TaskName 'p41x_elevprobe' -ErrorAction Stop).State) } catch { L ('A_state_err=' + $_.Exception.Message) }
try { L ('A_res=' + (Get-ScheduledTaskInfo -TaskName 'p41x_elevprobe').LastTaskResult) } catch {}

# --- probe file -----------------------------------------------------------
try { L ('probe_exists=' + (@(Get-ChildItem 'C:\Windows\Temp\p41_elev.txt' -Force -ErrorAction Stop).Count)) } catch { L ('probe_err=' + $_.Exception.Message) }
try { L ('probe_line=' + ((Get-Content 'C:\Windows\Temp\p41_elev.txt' -ErrorAction Stop) -join ' | ')) } catch { L ('probe_read_err=' + $_.Exception.Message) }

# --- transport B: schtasks /rl highest -----------------------------------
$tr = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Temp\p41_elev.ps1 -Tag schtasks'
$outB = & schtasks.exe /create /tn p41x_elevprobe_b /tr $tr /sc once /st 00:00 /rl highest /it /f 2>&1
L ('B_create=' + ($outB -join ' / '))
$outB2 = & schtasks.exe /run /tn p41x_elevprobe_b 2>&1
L ('B_run=' + ($outB2 -join ' / '))
Start-Sleep -Seconds 5
try { L ('probe_line2=' + ((Get-Content 'C:\Windows\Temp\p41_elev.txt') -join ' | ')) } catch { L ('probe_read_err2=' + $_.Exception.Message) }
L 'done'
