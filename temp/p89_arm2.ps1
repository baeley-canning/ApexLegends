# p89_arm2.ps1 -- re-arm the p64 listener after the 10:01 bugcheck killed it,
# prove it is up (R3 read-back), then enqueue job_p89.  Nothing here touches the
# driver; the listener itself is the elevated side.
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$out  = Join-Path $env:TEMP '_p89_arm2.txt'
"now=$(Get-Date -Format HH:mm:ss)" | Set-Content $out
Start-ScheduledTask -TaskName 'cheat_p64_arm' -EA SilentlyContinue
Start-Sleep -Seconds 6
Get-CimInstance Win32_Process -Filter "Name='python.exe'" -EA SilentlyContinue |
    Where-Object { $_.CommandLine -match 'p64_arm|arm' } |
    ForEach-Object { "listener pid=$($_.ProcessId) $($_.CommandLine)" } | Add-Content $out
(Get-ScheduledTask -TaskName 'cheat_p64_arm' -EA SilentlyContinue).State |
    ForEach-Object { "task_state=$_" } | Add-Content $out
$arm = Join-Path $root 'temp\arm.log'
if (Test-Path $arm) { "arm.log $((Get-Item $arm).LastWriteTime.ToString('HH:mm:ss'))" | Add-Content $out }
"done" | Add-Content $out
