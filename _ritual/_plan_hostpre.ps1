# _plan_hostpre.ps1 - read-only HOST pre-state before any h1 run (R3: pre must be recorded
# before the mutation, and only against this can a post-read mean anything). No writes, no driver.
$o = Join-Path $PSScriptRoot '_plan_hostpre.txt'
function W($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
if (Test-Path $o) { Remove-Item $o -Force }
W ('== host pre-state ' + (Get-Date -f 'dd/MM HH:mm:ss') + ' ==')
W ('boot: ' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('dd/MM HH:mm:ss'))
W ('uptime_min: ' + [int]((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalMinutes)
$q = (& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1) -join "`n"
W ('svc: ' + (($q -split "`n" | Where-Object { $_ -match 'STATE|FAILED' }) -join ' | ').Trim())
$qc = ((& "$env:SystemRoot\system32\sc.exe" qc apexdrv 2>&1) | Select-String 'EXIT_CODE')
W ('last_exit: ' + $(if ($qc) { $qc.Line.Trim() } else { 'no service object' }))
W ('minidumps: ' + @(Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -EA 0).Count)
W ((Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -EA 0 | Sort-Object LastWriteTime -Desc | Select-Object -First 4 | ForEach-Object { '  dump ' + $_.Name + ' ' + $_.LastWriteTime.ToString('dd/MM HH:mm') }) -join "`r`n")
W '--- 1001 bugchecks (last 6) ---'
W (((Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting' } -MaxEvents 6 -EA 0) | ForEach-Object { '  ' + $_.TimeCreated.ToString('dd/MM HH:mm') + ' ' + (($_.Message -split "`n")[0]) }) -join "`r`n")
W '--- 6008 unexpected shutdowns (last 4) ---'
W (((Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 6008 } -MaxEvents 4 -EA 0) | ForEach-Object { '  ' + $_.TimeCreated.ToString('dd/MM HH:mm') }) -join "`r`n")
W ('VBS: ' + ((Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -EA 0).VirtualizationBasedSecurityStatus))
W '--- game / ea ---'
W (((Get-Process EADesktop, EABackgroundService, r5apex, ApexLauncher, EasyAntiCheat -EA 0 | Select-Object -Expand Name -Unique) -join ', '))
W '-- end --'
