param([string]$CmdPath = 'C:\Users\New User\OneDrive\Desktop\cheating\temp\_h309_cmd.txt', [string]$ShotDir = 'C:\Users\New User\OneDrive\Desktop\cheating\temp')
$vb = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$type = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\_vmbench\type.ps1'
$log = Join-Path $ShotDir '_h311_drive.log'
function L($s) { Add-Content -LiteralPath $log -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) }
L 'start'
& $vb controlvm 'Win11-Test2' keyboardputscancode 01 81 | Out-Null      # Esc
Start-Sleep -Milliseconds 500
& $vb controlvm 'Win11-Test2' keyboardputscancode 5b 13 93 db | Out-Null # Win+R
Start-Sleep -Milliseconds 1500
L 'run dialog opened'
& $vb controlvm 'Win11-Test2' screenshotpng (Join-Path $ShotDir '_h311_a.png') | Out-Null
& powershell -NoProfile -ExecutionPolicy Bypass -File $type -Path $CmdPath | Out-Null
L 'typed'
Start-Sleep -Milliseconds 1000
& $vb controlvm 'Win11-Test2' screenshotpng (Join-Path $ShotDir '_h311_b.png') | Out-Null
& $vb controlvm 'Win11-Test2' keyboardputscancode 1c 9c | Out-Null        # Enter
Start-Sleep -Seconds 6
& $vb controlvm 'Win11-Test2' screenshotpng (Join-Path $ShotDir '_h311_c.png') | Out-Null
L 'entered'
Start-Sleep -Seconds 20
& $vb controlvm 'Win11-Test2' keyboardputscancode 1c 9c | Out-Null        # Enter for any UAC
Start-Sleep -Seconds 3
& $vb controlvm 'Win11-Test2' screenshotpng (Join-Path $ShotDir '_h311_d.png') | Out-Null
L 'done'
