# h130 - READ-ONLY pre-flight for the post-soak driver-load gate. No mutations.
# R5: own number, own output file, VERDICT line. R4: nothing to restore (read-only).
# Self-elevates once (bcdedit/sc need admin). Registers + starts the passive soak
# watcher h131 at the end so the whole phase needs exactly one UAC click.
$ErrorActionPreference = 'SilentlyContinue'
$tmp  = Join-Path (Split-Path -Parent $PSScriptRoot) 'temp'
$out  = Join-Path $tmp '_h130_out.txt'
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs -Wait
    Get-Content -LiteralPath $out
    exit 0
}
$m = @()
$os = Get-CimInstance Win32_OperatingSystem
$m += ('h130 ' + (Get-Date -f 'HH:mm:ss') + '  boot ' + $os.LastBootUpTime)
$m += ('uptime_min=' + [int]((Get-Date) - $os.LastBootUpTime).TotalMinutes)
# power / idle mitigation state
$q = (powercfg /qh scheme_current sub_processor idledisable) -join ' '
if ($q -match 'Current AC Power Setting Index: (0x\w+)') { $m += ('idledisable_ac=' + $Matches[1]) }
if ($q -match 'Current DC Power Setting Index: (0x\w+)') { $m += ('idledisable_dc=' + $Matches[1]) }
$m += ('restore_file=' + (Test-Path -LiteralPath (Join-Path $tmp '_p110_restore.txt')))
$m += ('scheme=' + ((powercfg /getactivescheme) -join ''))
# bcd flags (per R1: read-only, host-safe)
$b = (bcdedit /enum '{current}' 2>&1 | Out-String)
foreach ($k in 'testsigning','nointegritychecks','hypervisorlaunchtype','nx','bootmenupolicy') {
    if ($b -match ('(?m)^' + $k + '\s+(\S+)')) { $m += ('bcd_' + $k + '=' + $Matches[1]) } else { $m += ('bcd_' + $k + '=<absent>') }
}
# services + binPath
foreach ($s in 'apexdrv','gdrv3') {
    $r = (sc.exe query $s 2>&1 | Out-String)
    if ($r -match 'STATE\s+:\s+\d+\s+(\w+)') { $m += ('svc_' + $s + '=' + $Matches[1]) } else { $m += ('svc_' + $s + '=<absent>') }
    $bp = (Get-ItemProperty ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $s) -Name ImagePath).ImagePath
    $m += ('svc_' + $s + '_bin=' + $bp)
}
# dump config (the 0x124s leave no dumps - diagnose, don't fix here)
$cc = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
$m += ('dump_CrashDumpEnabled=' + (Get-ItemProperty $cc).CrashDumpEnabled)
$m += ('dump_AlwaysKeepMemoryDump=' + (Get-ItemProperty $cc).AlwaysKeepMemoryDump)
$m += ('dump_DedicatedDumpFile=' + (Get-ItemProperty $cc).DedicatedDumpFile)
$m += ('dump_pagefile_mb=' + ((Get-CimInstance Win32_PageFileUsage).AllocatedBaseSize))
$m += ('memorydmp=' + (Test-Path 'C:\Windows\MEMORY.DMP') + ' size=' + [int64]((Get-Item 'C:\Windows\MEMORY.DMP').Length))
$m += ('minidumps=' + (@(Get-ChildItem 'C:\Windows\Minidump' -EA SilentlyContinue).Count))
# today's counts + game
$d0 = (Get-Date).Date
$m += ('bugchecks_today=' + (@(Get-WinEvent -FilterHashtable @{LogName='System';Id=1001;StartTime=$d0} -EA SilentlyContinue).Count))
$m += ('whea18_today=' + (@(Get-WinEvent -FilterHashtable @{LogName='System';Id=18;StartTime=$d0} -EA SilentlyContinue).Count))
$m += ('game=' + ((@(Get-Process r5apex,r5apex_dx12,EADesktop -EA SilentlyContinue) | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ','))
$m += 'VERDICT PRE_CHECK_DONE (read-only)'
($m -join "`r`n") | Set-Content -LiteralPath $out -Encoding UTF8
# register + start passive soak watcher (h131, read-only loop, self-exits)
$hp = Join-Path $PSScriptRoot 'h131_soak.ps1'
$taskn = 'QwenKern_h131'
$arg = '-NoProfile -ExecutionPolicy Bypass -File "' + $hp + '"'
$a2 = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg -WorkingDirectory $PSScriptRoot
$p2 = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$s2 = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 60) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskn -Action $a2 -Principal $p2 -Settings $s2 -Force | Out-Null
Start-ScheduledTask -TaskName $taskn
Start-Sleep -Seconds 3
Add-Content -LiteralPath $out -Value ('soak_task=' + (Get-ScheduledTask -TaskName $taskn).State) -Encoding UTF8
Get-Content -LiteralPath $out
