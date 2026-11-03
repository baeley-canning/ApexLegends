# _plan_start10.ps1 - bench bring-up for the k10 fix soak. One variable: cur.ps1 = k10_soak.ps1.
# Fresh linked clone VM-D from p37-ready (G1), own snapshot pre-k10 (G2, revertable), payload
# server up (G3), VM started headless (G4). All read back to the log.
$VB  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$SRC = 'Win11-Test2'
$SNAP = 'p37-ready'
$VM  = 'VM-D'
$o   = Join-Path $PSScriptRoot '_plan_start10.txt'
function W($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
function VBX([string[]]$a) { (& $VB @a 2>&1) -join "`r`n" }
if (Test-Path $o) { Remove-Item $o -Force }
W ('== start10 ' + (Get-Date -f 'dd/MM HH:mm:ss') + ' ==')
W ('runningvms: ' + (VBX @('list', 'runningvms')))
$exists = ((& $VB list vms 2>&1) -join "`n") -match [regex]::Escape('"' + $VM + '"')
if ($exists) {
    W ('G1: ' + $VM + ' already registered - unregister+delete first')
    W ((VBX @('unregistervm', $VM, '--delete')))
}
W '--- G1 clone ---'
W ((VBX @('clonevm', $SRC, '--snapshot', $SNAP, '--options', 'link', '--name', $VM, '--register')))
W '--- G2 snapshot ---'
W ((VBX @('snapshot', $VM, 'take', 'pre-k10', '--description', 'before the k10 boot-value soak') ))
W ('snapshots now: ' + (((VBX @('snapshot', $VM, 'list')) -replace '\s+', ' ')))
W '--- G3 payload ---'
Copy-Item 'C:\p37vm\payload\k10_soak.ps1' 'C:\p37vm\payload\cur.ps1' -Force
Set-Content -LiteralPath 'C:\p37vm\payload\active.txt' -Value 'k10' -Encoding ascii
W ('cur.ps1 sha=' + (Get-FileHash 'C:\p37vm\payload\cur.ps1' -Algorithm SHA256).Hash.Substring(0, 16) + ' active=' + (Get-Content 'C:\p37vm\payload\active.txt'))
$srv = @(Get-NetTCPConnection -LocalPort 8080 -State Listen -EA 0).Count
if ($srv -eq 0) {
    Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', 'C:\p37vm\server.ps1') -WindowStyle Hidden
    Start-Sleep -Seconds 2
}
W ('G3 listen8080=' + @(Get-NetTCPConnection -LocalPort 8080 -State Listen -EA 0).Count)
W '--- G4 start ---'
W ((VBX @('startvm', $VM, '--type', 'headless')))
Start-Sleep -Seconds 4
W ('state: ' + (((VBX @('showvminfo', $VM, '--machinereadable')) | Select-String '^VMState').Line))
W '--- tail server.log ---'
W ((Get-Content 'C:\p37vm\server.log' -Tail 4 -EA 0) -join "`r`n")
W '-- end --'

