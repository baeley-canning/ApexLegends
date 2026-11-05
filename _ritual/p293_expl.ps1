# p293_expl.ps1 - probe #293 (variable: Explorer address bar as the type target)
# Safe-mode desktop menu has no 'Open in Terminal', so: taskbar Explorer (573,744) -> click the
# address bar (real Edit control, receives injected text even with the Start flyout broken) -> type
# 'powershell' -> Enter. Shots at every stage so a wrong stage is visible in the record.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p293.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
Say 'START'
Say (& (Join-Path $d 'vm_click.ps1') -X 573 -Y 744)
Start-Sleep -Seconds 4
& $v controlvm $VM screenshotpng (Join-Path $d 'p293_open.png') 2>&1 | Out-Null
Say 'shot open'
Say (& (Join-Path $d 'vm_click.ps1') -X 350 -Y 45)
Start-Sleep -Milliseconds 900
& $v controlvm $VM screenshotpng (Join-Path $d 'p293_bar.png') 2>&1 | Out-Null
Say 'shot bar'
K @('powershell'); Start-Sleep -Milliseconds 600
K @('enter'); Start-Sleep -Seconds 9
& $v controlvm $VM screenshotpng (Join-Path $d 'p293_ps.png') 2>&1 | Out-Null
Say 'shot ps'
Say 'END'