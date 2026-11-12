# _h304_shot.ps1 - state + one screenshot of the console, for a deliberate look before any click.
$vb = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$vm = 'Win11-Test2'
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\temp'
$o  = Join-Path $d '_h304_state.txt'
$m  = (& $vb showvminfo $vm --machinereadable) -join "`n"
$st = ([regex]::Match($m, '(?m)^VMState="([^"]+)"')).Groups[1].Value
$png = Join-Path $d '_h304_a.png'
Remove-Item -LiteralPath $png -Force -EA 0
& $vb controlvm $vm screenshotpng $png 2>&1 | Out-Null
$sz = 'FAIL'
if (Test-Path $png) { $sz = (Get-Item $png).Length.ToString() }
("state=$st shot=$sz png=$png") | Set-Content -LiteralPath $o -Encoding ascii
"state=$st shot=$sz"
