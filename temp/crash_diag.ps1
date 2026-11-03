# crash_diag.ps1 - read-only crash/reboot triage (writes temp\crash_diag.txt)
$ErrorActionPreference = 'Continue'
$o = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\crash_diag.txt'
$L = New-Object System.Collections.Generic.List[string]
function A($s) { $L.Add([string]$s) }

A ('now  ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
$os = Get-CimInstance Win32_OperatingSystem
A ('boot ' + $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss'))
A ('uptimeMin ' + [int]((Get-Date) - $os.LastBootUpTime).TotalMinutes)

A '--- events (10h: 41 1001 6008 1074 6005 6006 109 18 219) ---'
$t = (Get-Date).AddHours(-10)
try {
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=41,1001,6008,1074,6005,6006,109,18,219; StartTime=$t} -MaxEvents 60 -EA Stop |
        Sort-Object TimeCreated |
        ForEach-Object {
            $first = ($_.Message -split "`r?`n")[0]
            A ("{0}  id={1}  {2}  {3}" -f $_.TimeCreated.ToString('MM-dd HH:mm:ss'), $_.Id, $_.ProviderName, $first)
        }
} catch { A ('event-query failed: ' + $_.Exception.Message) }

A '--- minidumps (newest 8) ---'
try {
    Get-ChildItem 'C:\Windows\Minidump' -EA Stop | Sort-Object LastWriteTime -Descending |
        Select-Object -First 8 | ForEach-Object { A ("{0}  {1}  {2}" -f $_.Name, $_.Length, $_.LastWriteTime) }
} catch { A ('minidump dir: ' + $_.Exception.Message) }
A ('MEMORY.DMP=' + (Test-Path 'C:\Windows\MEMORY.DMP'))

A '--- LiveKernelReports newest 6 ---'
try {
    Get-ChildItem 'C:\Windows\LiveKernelReports' -Recurse -File -EA Stop |
        Sort-Object LastWriteTime -Descending | Select-Object -First 6 |
        ForEach-Object { A ("{0}  {1}" -f $_.FullName, $_.LastWriteTime) }
} catch { A ('lkr: ' + $_.Exception.Message) }

A '--- p40 dumplive state ---'
A ('p40d_out_exists=' + (Test-Path '_ritual\p40d_livedump.txt'))
if (Test-Path '_ritual\p40d_livedump.txt') { A (Get-Content '_ritual\p40d_livedump.txt' -Raw) }
A 'console:'
if (Test-Path 'temp\p40d_console.txt') { A (Get-Content 'temp\p40d_console.txt' -Raw) }
A 'err:'
if (Test-Path 'temp\p40d_err.txt') { A (Get-Content 'temp\p40d_err.txt' -Raw) }
Get-ChildItem 'temp\r5apex_live_*' -EA SilentlyContinue | ForEach-Object { A ("bin: {0} {1} {2}" -f $_.Name, $_.Length, $_.LastWriteTime) }

A '--- service / bcd ---'
(A ((sc.exe query apexdrv) -join ' | '))
(A ((bcdedit /enum '{current}') -join ' | '))

A '--- newer STATE.md entries (top 25 lines) ---'
if (Test-Path 'STATE.md') { Get-Content 'STATE.md' -TotalCount 25 | ForEach-Object { A $_ } }

Set-Content -LiteralPath $o -Value $L -Encoding UTF8
Write-Host ('WROTE ' + $o + ' lines=' + $L.Count)
