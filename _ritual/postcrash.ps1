# postcrash.ps1 -- read-only triage after an unexpected reboot. No device access.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$log  = Join-Path $repo 'temp\postcrash.log'
"=== postcrash $(Get-Date -Format o) ===" | Set-Content -Encoding utf8 $log
function L($t) { $t | Out-File -Append -Encoding utf8 $log }
$os = Get-CimInstance Win32_OperatingSystem
L ('boot=' + $os.LastBootUpTime)
L ('now=' + (Get-Date))
L ('uptime_min=' + [int]((Get-Date) - $os.LastBootUpTime).TotalMinutes)
L ('ram_total_gb=' + [math]::Round($os.TotalVisibleMemorySize / 1MB, 2))
L ('physmem_smBIOS_gb=' + [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2))
L ('dimm_sum_gb=' + [math]::Round((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1GB, 2))
L 'power41:'
try { Get-WinEvent -FilterHashtable @{ProviderName='Microsoft-Windows-Kernel-Power'; Id=41} -MaxEvents 5 -EA Stop | ForEach-Object { L ('  ' + $_.TimeCreated + ' | ' + (($_.Message -split "`n")[0])) } } catch { L ('  none/' + $_.Exception.Message) }
L 'bugcheck1001:'
try { Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; Id=1001} -MaxEvents 5 -EA Stop | ForEach-Object { L ('  ' + $_.TimeCreated + ' | ' + (($_.Message -split "`n")[0])) } } catch { L ('  none/' + $_.Exception.Message) }
L 'minidumps:'
Get-ChildItem 'C:\Windows\Minidump' -EA 0 | Sort-Object LastWriteTime -Desc | Select-Object -First 5 | ForEach-Object { L ('  ' + $_.LastWriteTime + ' ' + $_.Name + ' ' + $_.Length) }
L 'memory_dmp:'
Get-ChildItem 'C:\Windows\MEMORY.DMP' -EA 0 | ForEach-Object { L ('  ' + $_.LastWriteTime + ' ' + $_.Length) }
L 'listener_procs:'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'p64_arm|arm_task' } | ForEach-Object { L ('  pid=' + $_.ProcessId + ' :: ' + $_.CommandLine) }
L 'svc:'
Get-Service | Where-Object { $_.Name -match 'gio|gdrv' } | ForEach-Object { L ('  ' + $_.Name + ' ' + $_.Status + ' ' + $_.StartType) }
L 'game:'
L ('  ' + ((Get-Process r5apex_dx12 -EA 0 | Select-Object -First 1).Id))
L 'end'
