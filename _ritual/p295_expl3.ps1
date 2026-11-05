# p295_expl3.ps1 - probe #295 (variable: address bar at y=134, Explorer already open)
# #294 opened Explorer correctly but clicked the tab strip (y=45); the breadcrumb bar is at y=134 and
# clicking its empty stretch (520,134) turns it into an edit box.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p295.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
Say 'START'
Say (& (Join-Path $d 'vm_click.ps1') -X 520 -Y 134)
Start-Sleep -Milliseconds 900
& $v controlvm $VM screenshotpng (Join-Path $d 'p295_bar.png') 2>&1 | Out-Null
Say 'shot bar'
K @('powershell'); Start-Sleep -Milliseconds 600
K @('enter'); Start-Sleep -Seconds 10
& $v controlvm $VM screenshotpng (Join-Path $d 'p295_ps.png') 2>&1 | Out-Null
Say 'shot ps'
Say 'END'