# p277b_fp.ps1 - probe #277b (variable: win+R instead of win-search to open the shell)
# #277 proved the desktop is bare after win -> "powershell" -> enter: safe-mode Start search does
# not launch anything. Run dialog (winr) does not depend on search. Same read-only payload.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p277b.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function Typ($s) { & (Join-Path $d 'vm_type.ps1') -Seq @($s, 'enter') | Out-Null }
function State { (& $v showvminfo $VM --machinereadable | Select-String 'VMState="(\w+)"').Matches.Groups[1].Value }

Say ("START state={0}" -f (State))

& (Join-Path $d 'vm_type.ps1') -Seq @('winr') | Out-Null
Start-Sleep -Milliseconds 1200
& (Join-Path $d 'vm_type.ps1') -Seq @('powershell') | Out-Null
Start-Sleep -Milliseconds 500
& (Join-Path $d 'vm_type.ps1') -Seq @('enter') | Out-Null
Start-Sleep -Seconds 6
& $v controlvm $VM screenshotpng (Join-Path $d 'p277b_open.png') 2>&1 | Out-Null

Typ '[Environment]::OSVersion.Version'
Start-Sleep -Milliseconds 1200
Typ 'sc.exe query VBoxService'
Start-Sleep -Milliseconds 1200
Typ 'Get-CimInstance Win32_CDROMDrive | % { $_.Drive, $_.VolumeName }'
Start-Sleep -Milliseconds 1500
Typ "Get-WinEvent -FilterHashtable @{LogName='System';Id=41,1001,6008} -Max 5 | % { `$_.Id, `$_.TimeCreated }"
Start-Sleep -Milliseconds 2500

& $v controlvm $VM screenshotpng (Join-Path $d 'p277b_fp.png') 2>&1 | Out-Null
Say ("shot={0}" -f (Test-Path (Join-Path $d 'p277b_fp.png')))
Say 'VERDICT: shell open if p277b_open.png shows a window; read p277b_fp.png for the data'
Say 'END'
