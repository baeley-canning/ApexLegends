# p287_click.ps1 - probe #287 (variable: mouse click on the pinned PowerShell taskbar icon)
# Keyboard path is dead in this session (Start swallows letters). Taskbar PS icon in the guest is at
# 1024x768 pixel (728,744); vm_click maps it to host pixels over the window client rect.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p287.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
Say 'START'
Say (& (Join-Path $d 'vm_click.ps1') -X 728 -Y 744)
Start-Sleep -Seconds 6
& $v controlvm $VM screenshotpng (Join-Path $d 'p287_click.png') 2>&1 | Out-Null
Say 'shot'
Say 'END'
