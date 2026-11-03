# _plan_watch10.ps1 - read-only watcher for the k10 soak. Writes a compact status line set.
$o = Join-Path $PSScriptRoot '_plan_watch10.txt'
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
function W($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
if (Test-Path $o) { Remove-Item $o -Force }
$st = ((& $VB showvminfo VM-D --machinereadable 2>&1) | Select-String '^VMState=').Line
W ('now ' + (Get-Date -f 'HH:mm:ss') + '  vm=' + $st)
W ('gets=' + @(Select-String -Path 'C:\p37vm\server.log' -Pattern 'GET cur.ps1' -EA 0).Count)
W ('posts=' + @(Select-String -Path 'C:\p37vm\guest-k10.log' -Pattern '^===== POST' -EA 0).Count)
W '--- server.log tail ---'
W ((Get-Content 'C:\p37vm\server.log' -Tail 6 -EA 0) -join "`r`n")
W '--- guest-k10 tail ---'
W ((Get-Content 'C:\p37vm\guest-k10.log' -Tail 30 -EA 0) -join "`r`n")
W '-- end --'
