# _plan_boot11.ps1 - idempotent boot of VM-D after start11 was cut short at the startvm step.
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$o  = Join-Path $PSScriptRoot '_plan_boot11.txt'
function W($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
if (Test-Path $o) { Remove-Item $o -Force }
W ('== boot11 ' + (Get-Date -f 'HH:mm:ss') + ' ==')
$st = ((& $VB showvminfo VM-D --machinereadable 2>&1) | Select-String '^VMState=').Line
W ('state: ' + $st)
if ($st -match 'running') { W 'already running - no action' }
else {
    W ((& $VB startvm VM-D --type headless 2>&1) -join "`r`n")
    Start-Sleep -Seconds 5
    W ('state now: ' + (((& $VB showvminfo VM-D --machinereadable 2>&1) | Select-String '^VMState=').Line))
}
W '-- end --'
