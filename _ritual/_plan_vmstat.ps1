# _plan_vmstat.ps1 - read-only: VM states, snapshots, payload server, guest harness
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$o  = Join-Path $PSScriptRoot '_plan_vmstat.txt'
function W($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
if (Test-Path $o) { Remove-Item $o -Force }
W ('== vmstat ' + (Get-Date -f 'dd/MM HH:mm:ss') + ' ==')
W '--- vms ---'
W ((& $VB list vms 2>&1) -join "`r`n")
W '--- running ---'
W ((& $VB list runningvms 2>&1) -join "`r`n")
foreach ($v in 'Win11-Test2', 'VM-A', 'VM-B', 'VM-C') {
    $i = (& $VB showvminfo $v --machinereadable 2>&1) -join "`n"
    if ($i -match 'Could not find') { W ("$v : absent"); continue }
    $st = if ($i -match 'VMState="([^"]+)"') { $Matches[1] } else { '?' }
    $snap = ((& $VB snapshot $v list 2>&1) -join ' | ') -replace '\s+', ' '
    W ("$v : state=$st snapshots=$snap")
}
W '--- server 8080 ---'
$l = @(Get-NetTCPConnection -LocalPort 8080 -State Listen -EA 0)
W ('listen=' + $l.Count)
W ((Get-Process powershell -EA 0 | ForEach-Object { $_.Id.ToString() + ' ' + (Get-CimInstance Win32_Process -Filter ("ProcessId=" + $_.Id) -EA 0).CommandLine }) -join "`r`n")
W '--- guest log tail ---'
W ((Get-Content 'C:\p37vm\guest-k9.log' -Tail 12 -EA 0) -join "`r`n")
W '--- host game/eac ---'
W ((Get-Process r5apex, r5apex_dx12, EAAntiCheat*, EADesktop, EABackgroundService -EA 0 | ForEach-Object { $_.Name }) -join ',')
W '-- end --'
