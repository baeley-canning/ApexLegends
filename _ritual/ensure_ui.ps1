# ensure_ui.ps1 - guarantee a console window for the VM. A headless start (or a window that died on a
# guest crash) leaves the VM running with no window, and every click then silently goes nowhere.
# rc 0 = window present, rc 1 = could not get one. Reversible: it only starts/attaches, never powers off.
param([string]$VM = 'Win11-Test2', [int]$Wait = 45)
$d = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VV = 'C:\Program Files\Oracle\VirtualBox\VirtualBoxVM.exe'
function HasWin { ((& (Join-Path $d 'wins.ps1')) | Where-Object { $_ -match ' :: .*' + [regex]::Escape($VM) + '.* :: \d+x\d+' -and $_ -notmatch 'Restoring virtual' } | Measure-Object).Count -gt 0 }
if (HasWin) { 'window already present'; exit 0 }
$st = ((& $v showvminfo $VM --machinereadable | Select-String '^VMState=') -replace '.*=', '') -replace '"', ''
"state=$st"
if ($st -eq 'saved' -or $st -eq 'poweroff' -or $st -eq 'aborted') {
    Start-Process $VV -ArgumentList '--startvm', $VM
} elseif ($st -eq 'running') {
    & $v controlvm $VM savestate | Out-Null      # only way to get a UI onto a headless session
    Start-Sleep -Seconds 4
    Start-Process $VV -ArgumentList '--startvm', $VM
} else {
    # paused / restoring / stuck: give it a moment, then power-cycle
    Start-Sleep -Seconds 5
    if (-not (HasWin)) { & $v controlvm $VM poweroff | Out-Null; Start-Sleep -Seconds 4; Start-Process $VV -ArgumentList '--startvm', $VM }
}
for ($i = 0; $i -lt $Wait; $i++) {
    Start-Sleep -Seconds 2
    if (HasWin) { "window up after ${i}x2s"; exit 0 }
}
'no window obtained'; exit 1