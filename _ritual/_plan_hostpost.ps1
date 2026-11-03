# _plan_hostpost.ps1 - read-only HOST post-state + diff against _plan_hostpre.txt (R3 second half).
# Run ONLY after h1/h2, in the SAME boot (a rebooted boot time invalidates the comparison).
$o   = Join-Path $PSScriptRoot '_plan_hostpost.txt'
$pre = Join-Path $PSScriptRoot '_plan_hostpre.txt'
function W($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
if (Test-Path $o) { Remove-Item $o -Force }
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
W ('== host post-state ' + (Get-Date -f 'dd/MM HH:mm:ss') + ' ==')
W ('boot: ' + $boot.ToString('dd/MM HH:mm:ss') + '  uptime_min: ' + [int]((Get-Date) - $boot).TotalMinutes)
$preBoot = ((Select-String -Path $pre -Pattern '^boot: ').Line -replace '^boot: ', '')
W ('PRE-BOOT=' + $preBoot)
$q = (& "$env:SystemRoot\system32\sc.exe" query apexdrv 2>&1) -join ' '
W ('svc: ' + $(if ($q -match 'STATE\s+:\s+(\d+\s+\w+)') { $Matches[1] } else { 'ABSENT/FAILED' }))
W ('minidumps: ' + @(Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -EA 0).Count)
W ((Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -EA 0 | Sort-Object LastWriteTime -Desc | Select-Object -First 3 | ForEach-Object { '  dump ' + $_.Name + ' ' + $_.LastWriteTime.ToString('dd/MM HH:mm') }) -join "`r`n")
$new1001 = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; StartTime = $boot } -EA 0)
W ('bugchecks_this_boot: ' + $new1001.Count)
W ((($new1001 | ForEach-Object { '  ' + $_.TimeCreated.ToString('HH:mm') + ' ' + (($_.Message -split "`n")[0]) }) -join "`r`n"))
W '=== DIFF ==='
$preDumps = [int](((Select-String -Path $pre -Pattern '^minidumps: (\d+)').Line -split ': ')[1])
$nowDumps = @(Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -EA 0).Count
W ('dumps ' + $preDumps + ' -> ' + $nowDumps + '  ' + $(if ($nowDumps -gt $preDumps) { 'NEW DUMP' } else { 'no new dump' }))
W ('boot ' + $preBoot + ' -> ' + $boot.ToString('dd/MM HH:mm:ss') + '  ' + $(if ($preBoot -eq $boot.ToString('dd/MM HH:mm:ss')) { 'SAME BOOT' } else { 'REBOOTED - uptime diff invalid' }))
W ('-- end --')
