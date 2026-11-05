# p304_hang.ps1 - probe #304 (variable: measure whether the hung guest is spinning or idle)
# Frames since ~09:08 are pixel-identical and the guest clock is frozen at 09:05 while the host is at
# 09:17 - the guest is hung, that is why every session start sticks at "starting". CPU delta of the
# VM process separates a spin (100 %) from a stall (~0 %). Also grabs the host-side driver/GA view.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p304.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
Say 'START'
$p = Get-Process -Name 'VirtualBoxVM' -ErrorAction SilentlyContinue | Sort-Object CPU -Descending | Select-Object -First 1
if (-not $p) { Say 'no VirtualBoxVM process'; Say 'END'; return }
$c1 = $p.CPU
Say ('cpu1=' + $c1 + ' ws=' + $p.WorkingSet64)
Start-Sleep -Seconds 6
$p.Refresh()
Say ('cpu2=' + $p.CPU + ' delta=' + [math]::Round($p.CPU - $c1, 2))
Say ('state=' + ((& $v showvminfo $VM --machinereadable | Select-String 'VMState=') -replace 'VMState="', '' -replace '"', ''))
Say ('ga=' + ((& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=') -replace '.*=', ''))
& $v controlvm $VM screenshotpng (Join-Path $d 'p304_a.png') 2>&1 | Out-Null
Start-Sleep -Seconds 2
& $v controlvm $VM screenshotpng (Join-Path $d 'p304_b.png') 2>&1 | Out-Null
Say 'shots'
Say 'VERDICT: delta near 0 s in 6 s = stalled/soft hang, delta >= 5 s = spinning hang'
Say 'END'