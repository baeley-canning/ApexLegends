# p306_reset2.ps1 - probe #306 (variable: hard reset, spin detected by per-frame CPU delta)
# #305: guest frozen at clock 09:05 while the host ran to 09:18, VBoxHeadless burning ~400 % - a hard
# spin, not a stall. Reset and boot normal again, logging the VM process CPU delta every frame so the
# moment the spin starts is visible even before the picture freezes.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p306.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function VMP { Get-Process -Name 'VBoxHeadless' -ErrorAction SilentlyContinue | Sort-Object CPU -Descending | Select-Object -First 1 }
Say 'START'
& $v controlvm $VM reset 2>&1 | Out-Null
Start-Sleep -Seconds 5
Say ('after_reset state=' + ((& $v showvminfo $VM --machinereadable | Select-String 'VMState=') -replace 'VMState="', '' -replace '"', ''))
$prev = 0.0
for ($i = 1; $i -le 18; $i++) {
    Start-Sleep -Seconds 10
    $png = Join-Path $d ('p306_f{0}.png' -f $i)
    & $v controlvm $VM screenshotpng $png 2>&1 | Out-Null
    $p = VMP
    $cpu = 0.0; if ($p) { $cpu = $p.CPU }
    $delta = if ($prev -gt 0 -and $cpu -gt 0) { [math]::Round($cpu - $prev, 2) } else { 0 }
    $prev = $cpu
    $st = ((& $v showvminfo $VM --machinereadable | Select-String 'VMState=') -replace 'VMState="', '' -replace '"', '')
    $ga = ((& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=') -replace '.*=', '')
    $b = 0; if (Test-Path $png) { $b = (Get-Item $png).Length }
    Say ('f{0} state={1} bytes={2} ga={3} cpudelta={4}' -f $i, $st, $b, $ga, $delta)
}
Say 'VERDICT: pass if it reaches a desktop and no frame shows cpudelta > ~15 with frozen bytes'
Say 'END'