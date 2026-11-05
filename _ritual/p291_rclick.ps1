# p291_rclick.ps1 - probe #291 (variable: right-click reveals the true guest pointer position)
# Both x targets so far launched Store, so the mapping is unproven. Right-click on empty desktop: the
# context menu is drawn AT the guest pointer, which measures the drift directly - and the menu is a
# way to 'Open in Terminal' without the dead Start flyout.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p291.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
Say 'START'
Say (& (Join-Path $d 'vm_click.ps1') -X 823 -Y 45)   # close the Store window
Start-Sleep -Seconds 2
Say (& (Join-Path $d 'vm_click.ps1') -X 300 -Y 330 -Right)
Start-Sleep -Seconds 3
& $v controlvm $VM screenshotpng (Join-Path $d 'p291_menu.png') 2>&1 | Out-Null
Say 'shot'
Say 'END'