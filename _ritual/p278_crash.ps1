# p278_crash.ps1 - probe #278 (variable: none - crash identity; R8: 3 commands, ~15 s)
# #277b gave: VBoxService 1060 (GA genuinely absent), GA disc = F: (VBox_GA_7.2.22), and a
# 1001 BugCheck logged at 8:07:53 reporting the 2:46 reset (41/6008 pairs at both times).
# 1001 carries the bugcheck code + dump name - that decides whether this is the driver or VBox.
# Shell used is the already-open elevated PowerShell (safe mode = full admin, no UAC).
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p278.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function Typ($s) { & (Join-Path $d 'vm_type.ps1') -Seq @($s, 'enter') | Out-Null }

Say 'START'
Typ "Get-WinEvent -FilterHashtable @{LogName='System';Id=1001} -Max 2 | fl TimeCreated,Message"
Start-Sleep -Milliseconds 2000
Typ 'gci C:\Windows\Minidump -EA 0 | % { $_.Name, $_.Length, $_.LastWriteTime }'
Start-Sleep -Milliseconds 1500
Typ 'Get-WinEvent -FilterHashtable @{LogName="System";Id=41} -Max 2 | fl TimeCreated,Message'
Start-Sleep -Milliseconds 2000
& $v controlvm $VM screenshotpng (Join-Path $d 'p278_dump.png') 2>&1 | Out-Null
Say ("shot={0}" -f (Test-Path (Join-Path $d 'p278_dump.png')))
Say 'VERDICT: bugcheck code + dump present or not, from p278_dump.png'
Say 'END'
