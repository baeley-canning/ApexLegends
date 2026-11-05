# p301_look.ps1 - probe #301 (variable: look at the guest instead of poking guestcontrol)
# Three warm-ups in #300 all died in the same fixed 30 s "current status is: starting" - that is a
# broken session start, not slowness. Take plain frames first so the next step is chosen from evidence.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p301.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
Say 'START'
Say ('state=' + ((& $v showvminfo $VM --machinereadable | Select-String 'VMState=') -replace 'VMState="', '' -replace '"', ''))
Say ('ga=' + ((& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=') -replace '.*=', ''))
Say ('gaversion=' + ((& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsVersion=') -replace '.*=', ''))
& $v showvminfo $VM --machinereadable 2>&1 | Select-String 'GuestAdditionsStatusList|GuestAdditionsRunLevel|VMState=|DisplayName' | ForEach-Object { Say ('  ' + $_) }
& $v controlvm $VM screenshotpng (Join-Path $d 'p301_a.png') 2>&1 | Out-Null
Start-Sleep -Seconds 2
& $v controlvm $VM screenshotpng (Join-Path $d 'p301_b.png') 2>&1 | Out-Null
Say 'shots done'
Say 'END'