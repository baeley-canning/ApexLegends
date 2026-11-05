# p280_install.ps1 - probe #280 (variable: GA installed in safe mode from F:)
# #277b established: GA disc = F: (VBox_GA_7.2.22), VBoxService 1060, session already elevated via
# win+R (safe mode logon holds a full admin token - no Win+X/UAC chain needed).
# #272j proved this same installer works on this guest; the bits were lost to a snapshot revert,
# not to a failed install. Read-back gate: service RUNNING + VBox*.sys on disk + showvminfo ga>=1.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p280.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function Typ($s) { & (Join-Path $d 'vm_type.ps1') -Seq @($s, 'enter') | Out-Null }

Say 'START'
Say ('ga_before=' + ((& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=') -replace '.*=' ))
Typ 'F:\VBoxWindowsAdditions.exe /S'
Start-Sleep -Seconds 75
Say ('ga_after=' + ((& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=') -replace '.*=' ))

Typ 'sc.exe query VBoxService'
Start-Sleep -Milliseconds 1500
Typ 'gci C:\Windows\System32\drivers\VBox*.sys -EA 0 | % { $_.Name, $_.VersionInfo.FileVersion }'
Start-Sleep -Milliseconds 2000
Typ 'sc.exe start VBoxService'
Start-Sleep -Milliseconds 2500
Typ 'sc.exe query VBoxService'
Start-Sleep -Milliseconds 1500
& $v controlvm $VM screenshotpng (Join-Path $d 'p280_ga.png') 2>&1 | Out-Null
Say ('ga_final=' + ((& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=') -replace '.*=' ))
Say ("shot={0}" -f (Test-Path (Join-Path $d 'p280_ga.png')))
Say 'VERDICT: install PASS only if VBoxService is 4 RUNNING on the last query AND ga_final >= 1'
Say 'END'
