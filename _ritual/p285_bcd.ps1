# p285_bcd.ps1 - probe #285 (variable: single-batch winr, verified by shot before typing)
# #284 proved input reaches the guest (ESC closed the Start flyout); the Start search box itself is
# dead in this safe-mode session. #283b's per-key win,then-r failed; #277b's one-batch winr worked.
# So: batch winr, confirm the Run dialog on a shot, only then type.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p285.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
function Shot($n) { & $v controlvm $VM screenshotpng (Join-Path $d ('p285_' + $n + '.png')) 2>&1 | Out-Null; Say ('shot ' + $n) }

Say 'START'
K @('esc'); Start-Sleep -Milliseconds 900
K @('winr'); Start-Sleep -Milliseconds 2500
Shot 'run'
K @('powershell'); Start-Sleep -Milliseconds 500
K @('enter'); Start-Sleep -Seconds 10
Shot 'shell'
K @('cls'); Start-Sleep -Milliseconds 900
K @('bcdedit /enum all /v | sls "safeboot|descr"'); Start-Sleep -Seconds 5
K @("bcdedit /enum '{current}'"); Start-Sleep -Seconds 4
Shot 'a'
Start-Sleep -Seconds 4
Shot 'b'
Say 'END'
