# p89_procs.ps1 -- who is listening for the queue after the 10:01 crash?
# Get-CimInstance -Filter with a nested quote breaks from the chat one-liner, so
# the query lives in a file.  Read-only.
$out = Join-Path $env:TEMP '_p89_procs.txt'
"now=$(Get-Date -Format HH:mm:ss) uptime_min=$([math]::Round(((Get-Date)-(Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalMinutes,1))" | Set-Content $out
Get-CimInstance Win32_Process -Filter "Name='python.exe'" -EA SilentlyContinue |
    ForEach-Object { "pid=$($_.ProcessId) $($_.CommandLine)" } | Add-Content $out
Get-ScheduledTask -TaskName 'cheat_p64_arm' -EA SilentlyContinue |
    ForEach-Object { "task=$($_.TaskName) state=$($_.State)" } | Add-Content $out
Get-ChildItem (Join-Path $PSScriptRoot 'arm.log') -EA SilentlyContinue |
    ForEach-Object { "arm.log $($_.Length)B $($_.LastWriteTime.ToString('HH:mm:ss'))" } | Add-Content $out
"done" | Add-Content $out
