# p305_hang2.ps1 - probe #305 (variable: correct process name VBoxHeadless)
# #304 found no process because --type headless runs VBoxHeadless.exe. Same measurement, right name.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p305.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
Say 'START'
Get-Process -Name 'VBoxHeadless', 'VirtualBoxVM' -ErrorAction SilentlyContinue | ForEach-Object { Say ('proc {0} id={1} cpu={2}' -f $_.Name, $_.Id, $_.CPU) }
$p = Get-Process -Name 'VBoxHeadless', 'VirtualBoxVM' -ErrorAction SilentlyContinue | Sort-Object CPU -Descending | Select-Object -First 1
if (-not $p) { Say 'still no vm process'; Say 'END'; return }
$c1 = $p.CPU
Say ('cpu1=' + $c1 + ' ws=' + $p.WorkingSet64)
Start-Sleep -Seconds 6
$p.Refresh()
Say ('cpu2=' + $p.CPU + ' delta=' + [math]::Round($p.CPU - $c1, 2))
Say ('threads=' + $p.Threads.Count)
Say ('state=' + ((& $v showvminfo $VM --machinereadable | Select-String 'VMState=') -replace 'VMState="', '' -replace '"', ''))
Say ('ga=' + ((& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=') -replace '.*=', ''))
& $v controlvm $VM screenshotpng (Join-Path $d 'p305_a.png') 2>&1 | Out-Null
Start-Sleep -Seconds 2
& $v controlvm $VM screenshotpng (Join-Path $d 'p305_b.png') 2>&1 | Out-Null
Say 'shots'
Say 'VERDICT: delta near 0 s in 6 s = stalled, delta >= 5 s = spinning'
Say 'END'