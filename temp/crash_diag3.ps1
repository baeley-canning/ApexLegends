# crash_diag3.ps1 - read-only triage, NO WMI/CIM (CIM hangs on this boot)
$ErrorActionPreference = 'Continue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o = Join-Path $root 'temp\crash_diag3.txt'
$L = New-Object System.Collections.Generic.List[string]
function Flush { Set-Content -LiteralPath $o -Value $L -Encoding UTF8 }

$L.Add('now  ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
try { $b = (Get-Process -Id 4 -ErrorAction Stop).StartTime; $L.Add('boot ' + $b.ToString('yyyy-MM-dd HH:mm:ss')); $L.Add('uptimeMin ' + [int]((Get-Date) - $b).TotalMinutes) } catch { $L.Add('boot unknown: ' + $_.Exception.Message) }
$L.Add('--- proc ---')
Get-Process r5apex_dx12,R5apex,python,eadesktop -ErrorAction SilentlyContinue | ForEach-Object { $L.Add("proc: $($_.Name) $($_.Id) $($_.StartTime)") }
Flush

$L.Add('--- minidumps ---')
try { Get-ChildItem 'C:\Windows\Minidump' -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 8 | ForEach-Object { $L.Add("md: $($_.Name) $($_.Length) $($_.LastWriteTime)") } } catch { $L.Add('md: ' + $_.Exception.Message) }
$L.Add('MEMORY.DMP=' + (Test-Path 'C:\Windows\MEMORY.DMP'))
try { Get-ChildItem 'C:\Windows\LiveKernelReports' -File -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object { $L.Add("lkr: $($_.Name) $($_.LastWriteTime)") } } catch { $L.Add('lkr: ' + $_.Exception.Message) }
Flush

$L.Add('--- p40 ---')
$L.Add('p40d_out=' + (Test-Path "$root\_ritual\p40d_livedump.txt"))
try { $L.Add('console: ' + ((Get-Content "$root\temp\p40d_console.txt" -Raw -ErrorAction Stop) -replace "`r?`n", ' || ')) } catch { $L.Add('console: none') }
try { $L.Add('err: ' + ((Get-Content "$root\temp\p40d_err.txt" -Raw -ErrorAction Stop) -replace "`r?`n", ' || ')) } catch { $L.Add('err: none') }
Get-ChildItem "$root\temp\r5apex_live_*" -ErrorAction SilentlyContinue | ForEach-Object { $L.Add("bin: $($_.Name) $($_.Length) $($_.LastWriteTime)") }
$L.Add('--- svc ---')
$L.Add(((sc.exe query apexdrv) -join ' | '))
Flush

$L.Add('--- bcd ---')
$L.Add(((bcdedit /enum '{current}') -join ' | '))
$L.Add('--- EVENTLOG quick (last 25 sys 41/1001/6008/1074/109) ---')
try {
    $q = 'wevtutil qe System "/q:*[System[(EventID=41 or EventID=1001 or EventID=6008 or EventID=1074 or EventID=109)]]" /c:25 /rd:true /f:text'
    $out = cmd /c $q 2>&1
    $out | Select-Object -First 120 | ForEach-Object { $L.Add(($_ -replace "`r?`n", ' ')) }
} catch { $L.Add('wevt: ' + $_.Exception.Message) }
Flush

$L.Add('--- newest _ritual files ---')
Get-ChildItem "$root\_ritual" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 8 | ForEach-Object { $L.Add("f: $($_.Name) $($_.Length) $($_.LastWriteTime)") }
Flush
Write-Host ('DONE lines=' + $L.Count)
