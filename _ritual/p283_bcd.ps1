# p283_bcd.ps1 - probe #283 (variable: which entry holds safeboot)
# #281: bcdedit /deletevalue '{default}' safeboot printed SUCCESS, then poweroff+startvm came back
# into safe mode anyway (f4-f6 identical 24 KB frames, "Safe Mode" corner text). So either
# {default} is not the booted entry, or another entry carries the value. Measure before touching.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p283.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function Typ($s) { & (Join-Path $d 'vm_type.ps1') -Seq @($s, 'enter') | Out-Null }

Say 'START'
& (Join-Path $d 'vm_type.ps1') -Seq @('winr') | Out-Null
Start-Sleep -Milliseconds 1200
& (Join-Path $d 'vm_type.ps1') -Seq @('powershell') | Out-Null
Start-Sleep -Milliseconds 500
& (Join-Path $d 'vm_type.ps1') -Seq @('enter') | Out-Null
Start-Sleep -Seconds 6

Typ 'cls'
Start-Sleep -Milliseconds 500
Say 'A: every entry mentioning safeboot'
Typ 'bcdedit /enum all | Select-String "safeboot|identifier|description"'
Start-Sleep -Seconds 3
Say 'B: the default entry itself'
Typ "bcdedit /enum '{default}'"
Start-Sleep -Seconds 2
Say 'C: the booted entry (current)'
Typ "bcdedit /enum '{current}'"
Start-Sleep -Seconds 3
& $v controlvm $VM screenshotpng (Join-Path $d 'p283_bcd.png') 2>&1 | Out-Null
Say ("shot={0}" -f (Test-Path (Join-Path $d 'p283_bcd.png')))
Say 'VERDICT: read whether safeboot sits on {current} vs another entry, and whether a second Windows entry exists'
Say 'END'
