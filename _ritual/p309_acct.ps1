# p309_acct.ps1 - probe #309 (variable: guest is alive now, inspect vboxuser account)
# #308 opened the session but the logon was refused ("user was not able to logon"). The guest is not
# hung (clock matches the host, toasts keep appearing), so the account or its credential is the
# problem. Try Win+R again now that the desktop repaints; Explorer click as fallback.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p309.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
function Run([string]$c, [int]$w = 4) { K @($c); Start-Sleep -Milliseconds 350; K @('enter'); Start-Sleep -Seconds $w }
Say 'START'
K @('winr'); Start-Sleep -Milliseconds 1200
K @('powershell'); Start-Sleep -Milliseconds 400; K @('enter')
Start-Sleep -Seconds 6
& $v controlvm $VM screenshotpng (Join-Path $d 'p309_a.png') 2>&1 | Out-Null
Say 'winr shot'
Run 'whoami' 2
Run 'net user vboxuser' 3
Run 'net accounts' 2
& $v controlvm $VM screenshotpng (Join-Path $d 'p309_b.png') 2>&1 | Out-Null
Say 'END'