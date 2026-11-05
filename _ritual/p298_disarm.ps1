# p298_disarm.ps1 - probe #298 (variable: deletevalue on {current} with an on-screen read-back)
# #297: {default} == {current}, and safeboot Minimal is still there - #281's deletevalue reported
# success yet did not persist. So target {current} explicitly, then read the entry back in the same
# turn. No reboot unless the read-back shows safeboot gone.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p298.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
function Run([string]$c, [int]$w = 4) { K @($c); Start-Sleep -Milliseconds 400; K @('enter'); Start-Sleep -Seconds $w }
Say 'START'
Run 'cls' 1
Say 'A: delete'
Run "bcdedit /deletevalue '{current}' safeboot" 4
Say 'B: read-back'
Run "bcdedit /enum '{current}' | sls safeboot" 4
& $v controlvm $VM screenshotpng (Join-Path $d 'p298_a.png') 2>&1 | Out-Null
Say 'shot a'
Start-Sleep -Seconds 3
& $v controlvm $VM screenshotpng (Join-Path $d 'p298_b.png') 2>&1 | Out-Null
Say 'END'