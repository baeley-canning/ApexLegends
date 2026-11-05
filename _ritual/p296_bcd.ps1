# p296_bcd.ps1 - probe #296 (variable: BCD read-back through the working shell route)
# Route proven by #295: Explorer taskbar icon -> address bar edit -> 'powershell' -> elevated prompt.
# Now the actual payload: which entry still carries safeboot, and what {current}/{default} look like.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p296.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
Say 'START'
K @('cls'); Start-Sleep -Milliseconds 800
Say 'A: entries with safeboot'
K @('bcdedit /enum all | sls "safeboot|descr"'); Start-Sleep -Seconds 5
Say 'B: current'
K @("bcdedit /enum '{current}'"); Start-Sleep -Seconds 4
Say 'C: default'
K @("bcdedit /enum '{default}'"); Start-Sleep -Seconds 4
& $v controlvm $VM screenshotpng (Join-Path $d 'p296_a.png') 2>&1 | Out-Null
Say 'shot a'
Start-Sleep -Seconds 4
& $v controlvm $VM screenshotpng (Join-Path $d 'p296_b.png') 2>&1 | Out-Null
Say 'END'