# p277_fp.ps1 - probe #277 (variable: none, fingerprint + crash evidence; R7/R8 compliant)
# Guest is on the safe-mode desktop, GA ISO is at SATA-3-0, safeboot armed, GA not installed on
# this snapshot (pre-h268, build 26100). p272j.txt proves GA *was* installed at 22:43 on 26300 and
# was lost to a snapshot revert - so the install procedure is known good, the state is not.
# One decision: what is the pre-state to install against, and what actually resets the box.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p277.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function Typ($s) { & (Join-Path $d 'vm_type.ps1') -Seq @($s, 'enter') | Out-Null }
function State { (& $v showvminfo $VM --machinereadable | Select-String 'VMState="(\w+)"').Matches.Groups[1].Value }

Say 'START'
Say ("state={0}" -f (State))
Say ('snap=' + ((& $v snapshot $VM list --machinereadable | Select-String 'CurrentSnapshotName') -replace '.*=' ))
Say ('ga=' + ((& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=') -replace '.*=' ))
Say ('storage3=' + ((& $v showvminfo $VM --machinereadable | Select-String '"SATA-3-0"') -replace '.*=' ))

# open an elevated-free PowerShell (reads only): win -> powershell -> enter
& (Join-Path $d 'vm_type.ps1') -Seq @('win') | Out-Null
Start-Sleep -Milliseconds 900
& (Join-Path $d 'vm_type.ps1') -Seq @('powershell') | Out-Null
Start-Sleep -Milliseconds 400
& (Join-Path $d 'vm_type.ps1') -Seq @('enter') | Out-Null
Start-Sleep -Seconds 6

Typ '[Environment]::OSVersion.Version'
Start-Sleep -Milliseconds 1200
Typ 'sc.exe query VBoxService'
Start-Sleep -Milliseconds 1200
Typ 'Get-CimInstance Win32_CDROMDrive | % { $_.Drive, $_.VolumeName }'
Start-Sleep -Milliseconds 1500
Typ "Get-WinEvent -FilterHashtable @{LogName='System';Id=41,1001,6008} -Max 5 | % { `$_.Id, `$_.TimeCreated }"
Start-Sleep -Milliseconds 2500

& $v controlvm $VM screenshotpng (Join-Path $d 'p277_fp.png') 2>&1 | Out-Null
Say ("shot={0}" -f (Test-Path (Join-Path $d 'p277_fp.png')))
Say 'RESULT: fingerprint + cd drives + 41/1001/6008 in p277_fp.png'
Say 'VERDICT: proceed to install if a CD letter with a VBox disc is listed; if 1001 entries exist read the bugcheck code'
Say 'END'
