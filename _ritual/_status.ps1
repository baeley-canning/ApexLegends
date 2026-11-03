# _status.ps1 - one-shot status of the p36 run (no inline quoting games)
$b = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$nl = [char]10
$o = @()
try { $o += 'task_state=' + (Get-ScheduledTask -TaskName 'QwenKern_p36' -EA 0).State } catch { $o += 'task_state=?' }
$o += 'write_lines=' + (@(Get-Content "$b\p36_write.txt" -EA 0).Count)
$o += 'io_lines=' + (@(Get-Content "$b\p36_io.txt" -EA 0).Count)
$o += '-- write head/tail --'
$wl = @(Get-Content "$b\p36_write.txt" -EA 0)
$o += $wl | Select-Object -First 12
$o += '...'
$o += $wl | Select-Object -Last 14
$o += '-- io tail --'
$o += @(Get-Content "$b\p36_io.txt" -EA 0) | Select-Object -Last 8
$o += '-- bugchecks (25 min) --'
$o += @(Get-WinEvent -FilterHashtable @{LogName = 'System'; Id = 1001 } -MaxEvents 30 -EA 0 |
    Where-Object { $_.TimeCreated -gt (Get-Date).AddMinutes(-25) } |
    ForEach-Object { $_.TimeCreated.ToString('HH:mm:ss') + ' :: ' + ((($_.Message -split $nl)[0..3]) -join ' / ') })
$o += '-- procs --'
$o += @(Get-Process powershell -EA 0 | Select-Object Id, StartTime | ForEach-Object { $_.Id.ToString() + ' @ ' + $_.StartTime.ToString('HH:mm:ss') })
$o -join $nl | Out-File "$b\_t2.txt" -Encoding ascii
$o -join $nl
