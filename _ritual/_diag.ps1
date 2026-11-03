# _diag.ps1 - why did the p36 log stop at line 2?  Time the exact ops that follow it.
$b = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$nl = [char]10
$o = @()
$f = Get-Item "$b\p36_write.txt" -EA 0
if ($f) { $o += "writefile len=$($f.Length) lastwrite=$($f.LastWriteTime.ToString('HH:mm:ss.fff'))" }
$fi = Get-Item "$b\p36_io.txt" -EA 0
$o += "iofile " + $(if ($fi) { "len=$($fi.Length) lastwrite=$($fi.LastWriteTime.ToString('HH:mm:ss.fff'))" } else { 'MISSING' })
$o += "taskinfo " + ((Get-ScheduledTaskInfo -TaskName 'QwenKern_p36' -EA 0 | Select-Object LastRunTime, LastTaskResult, NumberOfMissedRuns | Out-String -Width 120).Trim())

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$os = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 25 -EA 0
$o += "T_cim_os_ms=$($sw.ElapsedMilliseconds) caption=[$($os.Caption)] build=$($os.BuildNumber) ver=$($os.Version)"
$sw.Restart()
$pr = Get-CimInstance Win32_Processor -OperationTimeoutSec 25 -EA 0 | Select-Object -First 1
$o += "T_cim_cpu_ms=$($sw.ElapsedMilliseconds) name=[$($pr.Name)]"

$p = Get-Process -Id 19348 -EA 0
if ($p) {
    $o += "pid19348 cpu=$($p.CPU) ws=$([int]($p.WorkingSet64/1MB))MB thr=$($p.Threads.Count) start=$($p.StartTime.ToString('HH:mm:ss')) responding=$($p.Responding)"
    $c1 = $p.CPU
    Start-Sleep -Seconds 6
    $p2 = Get-Process -Id 19348 -EA 0
    if ($p2) { $o += "pid19348 cpu_after_6s=$($p2.CPU) delta=$([math]::Round($p2.CPU - $c1, 3)) thr=$($p2.Threads.Count)" } else { $o += 'pid19348 gone' }
} else { $o += 'pid19348 GONE' }
$o += 'csc=' + (@(Get-Process csc -EA 0).Count) + ' powershell_count=' + (@(Get-Process powershell -EA 0).Count)
$o += '-- p36_write.txt raw --'
$o += Get-Content "$b\p36_write.txt" -Raw -EA 0
$o += '-- p36_io.txt raw --'
$o += Get-Content "$b\p36_io.txt" -Raw -EA 0
$o -join $nl | Set-Content "$b\_diag.txt" -Encoding ascii
