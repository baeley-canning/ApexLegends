# p279_codes.ps1 - probe #279 (variable: none - bugcheck code + faulting modules from the dumps)
# #278 found 4 real kernel minidumps in C:\Windows\Minidump (110626-6531, -9625, -10593, -9171,
# 1.1-1.2 MB each). Those are the crash identity the reset timer never let us read off the screen.
# 1001 messages carry the bugcheck code; minidumps carry the loaded module list as UTF-16, so a
# unicode Select-String for *.sys names is enough to name candidates without a debugger.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p279.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function Typ($s) { & (Join-Path $d 'vm_type.ps1') -Seq @($s, 'enter') | Out-Null }

Say 'START'
Typ 'cls'
Start-Sleep -Milliseconds 600
Typ "Get-WinEvent -FilterHashtable @{LogName='System';Id=1001} -Max 3 | % { `$_.TimeCreated; `$_.Message }"
Start-Sleep -Milliseconds 2500
Typ 'gci C:\Windows\Minidump\*.dmp | % { $_.Name; (Select-String -Path $_.FullName -Pattern "([\w-]+\.sys)" -AllMatches -Encoding unicode).Matches.Value | sort -Unique }'
Start-Sleep -Seconds 4
& $v controlvm $VM screenshotpng (Join-Path $d 'p279_codes.png') 2>&1 | Out-Null
Say ("shot={0}" -f (Test-Path (Join-Path $d 'p279_codes.png')))
Say 'VERDICT: bugcheck codes + .sys module names per dump, from p279_codes.png'
Say 'END'
