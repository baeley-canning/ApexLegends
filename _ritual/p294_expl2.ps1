# p294_expl2.ps1 - probe #294 (variable: Explorer at x=613, not 573 which is Task View)
# #293 clicked 573 = Task View. The folder icon sits at 613. Same chain, corrected target, and the
# address-bar click goes to the empty stretch right of the breadcrumbs (600,45) so it turns into an
# edit box rather than opening a breadcrumb.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p294.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
Say 'START'
K @('esc'); Start-Sleep -Milliseconds 600
Say (& (Join-Path $d 'vm_click.ps1') -X 613 -Y 744)
Start-Sleep -Seconds 4
& $v controlvm $VM screenshotpng (Join-Path $d 'p294_open.png') 2>&1 | Out-Null
Say 'shot open'
Say (& (Join-Path $d 'vm_click.ps1') -X 600 -Y 45)
Start-Sleep -Milliseconds 900
& $v controlvm $VM screenshotpng (Join-Path $d 'p294_bar.png') 2>&1 | Out-Null
Say 'shot bar'
K @('powershell'); Start-Sleep -Milliseconds 600
K @('enter'); Start-Sleep -Seconds 9
& $v controlvm $VM screenshotpng (Join-Path $d 'p294_ps.png') 2>&1 | Out-Null
Say 'shot ps'
Say 'END'