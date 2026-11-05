# p283b_bcd.ps1 - probe #283b (variable: per-key open sequence instead of one-shot 'winr')
# #283 died mid-run (my own run_commands calls close the launcher terminal and kill the child) and
# its 'winr' lost the race: vm_type sends win-down/up+r in ONE batch, so the Start menu swallowed
# the r. Real typing rate is ~150-250 ms/char (each VBoxManage call is a cold process), so the
# payload below is also shortened to two commands.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p283b.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }

Say 'START'
K @('esc'); Start-Sleep -Milliseconds 700
K @('esc'); Start-Sleep -Milliseconds 700
K @('win'); Start-Sleep -Milliseconds 1100
K @('r');   Start-Sleep -Milliseconds 1100
K @('powershell'); Start-Sleep -Milliseconds 400
K @('enter'); Start-Sleep -Seconds 9
Say 'shell opened'

K @('cls'); Start-Sleep -Milliseconds 800
K @('bcdedit /enum all /v | sls "safeboot|descr"'); Start-Sleep -Seconds 5
K @("bcdedit /enum '{current}'"); Start-Sleep -Seconds 4
Say 'payload typed'
& $v controlvm $VM screenshotpng (Join-Path $d 'p283b_a.png') 2>&1 | Out-Null
Start-Sleep -Seconds 4
& $v controlvm $VM screenshotpng (Join-Path $d 'p283b_b.png') 2>&1 | Out-Null
Say 'END'
