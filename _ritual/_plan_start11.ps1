# _plan_start11.ps1 - re-arm the bench after the k10 abort (DrvState undefined -> DSE left at 0).
# Revert VM-D to pre-k10 (R4: the abort left the guest mutated), swap cur.ps1 to k11, boot.
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$o  = Join-Path $PSScriptRoot '_plan_start11.txt'
function W($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
function VBX([string[]]$a) { (& $VB @a 2>&1) -join "`r`n" }
if (Test-Path $o) { Remove-Item $o -Force }
W ('== start11 ' + (Get-Date -f 'dd/MM HH:mm:ss') + ' ==')
W ('state before: ' + (((VBX @('showvminfo', 'VM-D', '--machinereadable')) | Select-String '^VMState').Line))
W '--- revert to pre-k10 ---'
W ((VBX @('controlvm', 'VM-D', 'poweroff')))
Start-Sleep -Seconds 6
W ((VBX @('snapshot', 'VM-D', 'restore', 'pre-k10')))
W ('state after revert: ' + (((VBX @('showvminfo', 'VM-D', '--machinereadable')) | Select-String '^VMState').Line))
W ('snapshots: ' + (((VBX @('snapshot', 'VM-D', 'list')) -replace '\s+', ' ')))
W '--- payload swap ---'
Copy-Item 'C:\p37vm\payload\k11_soak.ps1' 'C:\p37vm\payload\cur.ps1' -Force
Set-Content -LiteralPath 'C:\p37vm\payload\active.txt' -Value 'k11' -Encoding ascii
W ('cur.ps1 sha=' + (Get-FileHash 'C:\p37vm\payload\cur.ps1' -Algorithm SHA256).Hash.Substring(0, 16) + ' len=' + (Get-Item 'C:\p37vm\payload\cur.ps1').Length + ' active=' + (Get-Content 'C:\p37vm\payload\active.txt'))
W ('listen8080=' + @(Get-NetTCPConnection -LocalPort 8080 -State Listen -EA 0).Count)
W '--- boot ---'
W ((VBX @('startvm', 'VM-D', '--type', 'headless')))
Start-Sleep -Seconds 4
W ('state final: ' + (((VBX @('showvminfo', 'VM-D', '--machinereadable')) | Select-String '^VMState').Line))
W '-- end --'
