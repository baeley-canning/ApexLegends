# p311_pw.ps1 - probe #311 (variable: reset vboxuser's password in-guest, verify the account)
# #308 session opened but the logon was refused. Nothing else in this VM changed except the GA
# reinstall, and #310 shows a fast crash-reset cycle, so the account state is checked before the GA is
# blamed. Explorer -> address bar -> powershell, then read the account and force a known password.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p311.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
function Run([string]$c, [int]$w = 3) { K @($c); Start-Sleep -Milliseconds 350; K @('enter'); Start-Sleep -Seconds $w }
Say 'START'
& (Join-Path $d 'vm_click.ps1') -X 613 -Y 744 | Out-Null
Start-Sleep -Seconds 3
& $v controlvm $VM screenshotpng (Join-Path $d 'p311_exp.png') 2>&1 | Out-Null
& (Join-Path $d 'vm_click.ps1') -X 520 -Y 134 | Out-Null
Start-Sleep -Milliseconds 900
K @('powershell'); Start-Sleep -Milliseconds 400; K @('enter')
Start-Sleep -Seconds 7
& $v controlvm $VM screenshotpng (Join-Path $d 'p311_ps.png') 2>&1 | Out-Null
Say 'shell attempt done'
Run 'whoami' 2
Run 'net user vboxuser' 3
Run 'net user vboxuser vboxuser' 3
& $v controlvm $VM screenshotpng (Join-Path $d 'p311_a.png') 2>&1 | Out-Null
Say 'a'
Run 'net user vboxuser | findstr /i "active expires password"' 3
& $v controlvm $VM screenshotpng (Join-Path $d 'p311_b.png') 2>&1 | Out-Null
Say 'END'