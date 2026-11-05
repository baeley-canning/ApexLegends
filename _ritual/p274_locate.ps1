# p274_locate.ps1 - probe #274 (variable: PS-correct syntax on the ALREADY-elevated shell)
# #273 proved: elevation works (title "Administrator: Windows PowerShell"), but the shell is
# PowerShell, so (a) {default} is eaten as a script block, (b) cd to the assumed GA dir failed
# because "C:\Program Files\Oracle\VirtualBox Guest Additions" does not exist, (c) `sc` is the
# Set-Content alias and silently wrote a file instead of calling the SCM.
# This probe: correct bcdedit quoting, then LOCATE the real GA bits, then bugcheck evidence.
# Reuses the open elevated window - no second UAC.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$log = Join-Path $d 'p274.log'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $log -Encoding ascii -Append }
function State { (& $v showvminfo $VM --machinereadable | Select-String 'VMState="(\w+)"').Matches.Groups[1].Value }
function Shot($n) { & $v controlvm $VM screenshotpng (Join-Path $d $n) 2>&1 | Out-Null }
function Typ($s) { & (Join-Path $d 'vm_type.ps1') -Seq @($s, 'enter') | Out-Null }

Say 'start'
Say "pre VMState=$(State)"

# 1) safeboot with the braces quoted so PowerShell passes them through
Typ "bcdedit /set '{default}' safeboot minimal"
Start-Sleep -Milliseconds 1200
Shot 'p274_bcd.png'
Say 'bcdedit quoted-brace sent'

# 2) locate: which VBox services exist, where the GA files live, driver files present
Typ 'Get-Service *vbox* -EA 0'
Start-Sleep -Milliseconds 1000
Typ 'gci C:\Windows\System32\drivers -Filter VBo* -EA 0 | % Name'
Start-Sleep -Milliseconds 1000
Typ "gci 'C:\Program Files' -Filter VBox* -Recurse -Depth 3 -EA 0 | % FullName"
Start-Sleep -Milliseconds 1500
Typ "gci C:\ -Filter VBoxService.exe -Recurse -Depth 2 -EA 0 | % FullName"
Start-Sleep -Milliseconds 1500
Shot 'p274_loc.png'
Say 'locate done'

# 3) what actually killed it: 41 = kernel-power, 1001 = bugcheck, 6008 = unexpected shutdown
Typ "Get-WinEvent -FilterHashtable @{LogName='System';Id=41,1001,6008} -Max 5 | % { '{0} {1}' -f `$_.Id, `$_.TimeCreated }"
Start-Sleep -Milliseconds 2500
Shot 'p274_ev.png'
Say 'event query done'

Say ("RESULT: state={0} shots={1}" -f (State), (@('p274_bcd.png','p274_loc.png','p274_ev.png') | ? { Test-Path (Join-Path $d $_) }).Count)
Say 'VERDICT: read p274_bcd.png (safeboot), p274_loc.png (GA path), p274_ev.png (crash cause)'
Say 'done'
