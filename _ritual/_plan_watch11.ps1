# _plan_watch11.ps1 - read-only watcher for the k11 soak. Own output, own guest log.
$o  = Join-Path $PSScriptRoot '_plan_watch11.txt'
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$g  = 'C:\p37vm\guest-k11.log'
function W($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
if (Test-Path $o) { Remove-Item $o -Force }
$st = ((& $VB showvminfo VM-D --machinereadable 2>&1) | Select-String '^VMState=').Line
W ('now ' + (Get-Date -f 'HH:mm:ss') + '  vm=' + $st + '  k11log=' + (Test-Path $g))
W ('gets_cur=' + @(Select-String -Path 'C:\p37vm\server.log' -Pattern 'GET cur.ps1' -EA 0).Count)
W ('posts=' + @(Select-String -Path $g -Pattern '^===== POST' -EA 0).Count)
W ('pre=' + (((Select-String -Path $g -Pattern 'PRE-DSE=' -EA 0).Line) -join ' | '))
W ('restore=' + (((Select-String -Path $g -Pattern 'RESTORE ' -EA 0).Line) -join ' | '))
W ('hbs=' + @(Select-String -Path $g -Pattern '^HB ' -EA 0).Count + '  last=' + (((Select-String -Path $g -Pattern '^HB ' -EA 0).Line | Select-Object -Last 1)))
W '--- guest tail ---'
W ((Get-Content $g -Tail 22 -EA 0) -join "`r`n")
W '-- end --'
