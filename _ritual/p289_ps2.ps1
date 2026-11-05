# p289_ps2.ps1 - probe #289 (variable: re-click on an already-hovered icon)
# #288's warm-up click closed the Store window and left the pointer on the PowerShell icon (tooltip
# confirms). The launch click was swallowed, so repeat it once with the hover already established.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p289.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
Say 'START'
Say (& (Join-Path $d 'vm_click.ps1') -X 728 -Y 744)
Start-Sleep -Seconds 10
& $v controlvm $VM screenshotpng (Join-Path $d 'p289_ps.png') 2>&1 | Out-Null
Say 'shot'
Say 'END'
