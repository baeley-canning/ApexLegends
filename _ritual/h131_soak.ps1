# h131 - PASSIVE soak watcher. Read-only, 1 sample/min, early exit on a new bugcheck.
# Purpose: prove or disprove host stability with idle-disable active and ZERO probe load
# before any driver/GIO work resumes (R5 one variable: nothing runs, only counts move).
# Log: temp\_h131_soak.log ; verdict lines: SOAK_VERDICT CRASH|CLEAN.
$ErrorActionPreference = 'SilentlyContinue'
$tmp = Join-Path (Split-Path -Parent $PSScriptRoot) 'temp'
$log = Join-Path $tmp '_h131_soak.log'
$d0  = (Get-Date).Date
function BC { @(Get-WinEvent -FilterHashtable @{LogName='System';Id=1001;StartTime=$d0} -EA SilentlyContinue).Count }
$bc0 = BC
Add-Content -LiteralPath $log -Value ('SOAK_START ' + (Get-Date -f 'HH:mm:ss') + ' bc0=' + $bc0) -Encoding UTF8
$n = 0
while ($n -lt 40) {
    $n++
    $os = Get-CimInstance Win32_OperatingSystem
    $bc = BC
    $w  = @(Get-WinEvent -FilterHashtable @{LogName='System';Id=18;StartTime=$d0} -EA SilentlyContinue).Count
    $line = '{0} #{1} up={2}min bc={3} w18={4} svc_apexdrv=' -f (Get-Date -f 'HH:mm:ss'), $n, [int]((Get-Date) - $os.LastBootUpTime).TotalMinutes, $bc, $w
    $svc = (sc.exe query apexdrv 2>&1 | Out-String)
    if ($svc -match 'STATE\s+:\s+\d+\s+(\w+)') { $line += $Matches[1] } else { $line += '?' }
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    if ($bc -gt $bc0) { Add-Content -LiteralPath $log -Value ('SOAK_VERDICT CRASH at ' + (Get-Date -f 'HH:mm:ss')); exit 1 }
    Start-Sleep -Seconds 60
}
Add-Content -LiteralPath $log -Value ('SOAK_VERDICT CLEAN 40 samples ' + (Get-Date -f 'HH:mm:ss'))
