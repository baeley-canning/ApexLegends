# p288_ps.ps1 - probe #288 (variable: warm-up click to establish the pointer grab, then hit the PS icon)
# #287 clicked, but the guest pointer is relative (no mouse integration in safe mode), so the first
# click landed on Store. A warm-up click syncs the pointer, the second one is 1:1 on the corrected map.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p288.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
Say 'START'
Say (& (Join-Path $d 'vm_click.ps1') -X 300 -Y 330)
Start-Sleep -Milliseconds 700
Say (& (Join-Path $d 'vm_click.ps1') -X 728 -Y 744)
Start-Sleep -Seconds 6
& $v controlvm $VM screenshotpng (Join-Path $d 'p288_ps.png') 2>&1 | Out-Null
Say 'shot'
Say 'END'
