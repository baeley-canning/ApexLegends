# p302_gadiag.ps1 - probe #302 (variable: read VBoxService from inside the guest)
# ga=3 but every session start sticks at "starting" - either VBoxService is dead (and only the driver
# reports the level) or it faults while creating the session. Open Explorer -> address bar ->
# powershell (route proven in p294), then read service state, the vboxuser account and VBoxService.log.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p302.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
function Run([string]$c, [int]$w = 4) { K @($c); Start-Sleep -Milliseconds 350; K @('enter'); Start-Sleep -Seconds $w }
Say 'START'
& (Join-Path $d 'vm_click.ps1') -X 613 -Y 744 | Out-Null
Start-Sleep -Seconds 3
Say 'explorer'
& (Join-Path $d 'vm_click.ps1') -X 520 -Y 134 | Out-Null
Start-Sleep -Milliseconds 800
K @('powershell'); Start-Sleep -Milliseconds 350; K @('enter')
Start-Sleep -Seconds 7
& $v controlvm $VM screenshotpng (Join-Path $d 'p302_ps.png') 2>&1 | Out-Null
Say 'shell'
Run 'Get-Service VBoxService,VBoxMouse,VBoxSF,VBoxGuest | fl Name,Status,StartType' 4
Run 'net user vboxuser' 3
Run 'gci C:\Windows\System32\LogFiles\VBox\*.log -EA 0 | % { $_.Name; Get-Content $_.FullName -Tail 12 }' 5
& $v controlvm $VM screenshotpng (Join-Path $d 'p302_a.png') 2>&1 | Out-Null
Say 'a'
Start-Sleep -Seconds 3
& $v controlvm $VM screenshotpng (Join-Path $d 'p302_b.png') 2>&1 | Out-Null
Say 'END'