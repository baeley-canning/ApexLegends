# p290_cal.ps1 - probe #290 (variable: +35 px x bias to cancel the pointer undershoot)
# #287 and #289 both targeted guest x=728 on the taskbar and both launched STORE, whose icon sits at
# ~693: the guest pointer undershoots by ~35 px (relative/accelerated PS/2 mapping, no integration
# in safe mode). Click the compensated x and see which app actually opens.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p290.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
Say 'START'
Say (& (Join-Path $d 'vm_click.ps1') -X 763 -Y 744)
Start-Sleep -Seconds 9
& $v controlvm $VM screenshotpng (Join-Path $d 'p290_cal.png') 2>&1 | Out-Null
Say 'shot'
Say 'END'
