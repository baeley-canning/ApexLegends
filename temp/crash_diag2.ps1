# crash_diag2.ps1 - minimal, read-only; writes temp\crash_diag2.txt
$ErrorActionPreference = 'Continue'
$o = Join-Path $PSScriptRoot 'crash_diag2.txt'
$L = New-Object System.Collections.Generic.List[string]
$L.Add('now  ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
try { $os = Get-CimInstance Win32_OperatingSystem; $L.Add('boot ' + $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')); $L.Add('uptimeMin ' + [int]((Get-Date) - $os.LastBootUpTime).TotalMinutes) } catch { $L.Add('os fail: ' + $_.Exception.Message) }
Set-Content -LiteralPath $o -Value $L -Encoding UTF8

$L.Add('--- minidumps ---')
try { Get-ChildItem 'C:\Windows\Minidump' -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 8 | ForEach-Object { $L.Add("$($_.Name) $($_.Length) $($_.LastWriteTime)") } } catch { $L.Add('md: ' + $_.Exception.Message) }
$L.Add('MEMORY.DMP=' + (Test-Path 'C:\Windows\MEMORY.DMP'))
try { Get-ChildItem 'C:\Windows\LiveKernelReports' -File -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object { $L.Add("lkr: $($_.Name) $($_.LastWriteTime)") } } catch { $L.Add('lkr: ' + $_.Exception.Message) }

$L.Add('--- p40 ---')
$L.Add('p40d_out=' + (Test-Path 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\p40d_livedump.txt'))
try { $L.Add('console: ' + ((Get-Content 'C:\Users\New User\OneDrive\Desktop\cheating\temp\p40d_console.txt' -Raw -ErrorAction Stop) -replace "`r?`n", ' || ')) } catch { $L.Add('console: none') }
try { $L.Add('err: ' + ((Get-Content 'C:\Users\New User\OneDrive\Desktop\cheating\temp\p40d_err.txt' -Raw -ErrorAction Stop) -replace "`r?`n", ' || ')) } catch { $L.Add('err: none') }
Get-ChildItem 'C:\Users\New User\OneDrive\Desktop\cheating\temp\r5apex_live_*' -ErrorAction SilentlyContinue | ForEach-Object { $L.Add("bin: $($_.Name) $($_.Length) $($_.LastWriteTime)") }

$L.Add('--- svc ---')
$L.Add(((sc.exe query apexdrv) -join ' | '))
Set-Content -LiteralPath $o -Value $L -Encoding UTF8

$L.Add('--- bcd ---')
$L.Add(((bcdedit /enum '{current}') -join ' | '))
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
Write-Host ('WROTE lines=' + $L.Count)
