# p292_legacy.ps1 - probe #292 (variable: 'Show more options' -> 'Open in Terminal')
# #291 proved the mapping is exact (menu opened at the exact click point), so the taskbar icon at 728
# is simply not PowerShell. The classic desktop menu carries 'Open in Terminal', which needs no Start
# flyout and no typed command. Step 1: open the legacy menu and screenshot it.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p292.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
Say 'START'
Say (& (Join-Path $d 'vm_click.ps1') -X 392 -Y 566)
Start-Sleep -Seconds 3
& $v controlvm $VM screenshotpng (Join-Path $d 'p292_legacy.png') 2>&1 | Out-Null
Say 'shot'
Say 'END'