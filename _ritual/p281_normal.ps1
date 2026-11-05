# p281_normal.ps1 - probe #281 (variable: safeboot disarmed -> normal boot with GA installed)
# Gate: GA proven first (p280: service RUNNING + ga>=1). Safe mode has no ACPI shutdown, so the
# cycle is bcdedit -> poweroff -> startvm. Watch 12 frames at 10 s: a desktop frame with a taskbar
# and no new Id=41 means the box survived normal boot; a black frame means the reset is back.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p281.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function Typ($s) { & (Join-Path $d 'vm_type.ps1') -Seq @($s, 'enter') | Out-Null }
function State { (& $v showvminfo $VM --machinereadable | Select-String 'VMState="(\w+)"').Matches.Groups[1].Value }
function Ga { (& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=') -replace '.*=' }

Say ("START state={0}" -f (State))
# disarm safe mode (single-quoted template: bare {default} is eaten as a script block in PS)
Typ "bcdedit /deletevalue '{default}' safeboot"
Start-Sleep -Seconds 2
& $v controlvm $VM screenshotpng (Join-Path $d 'p281_bcd.png') 2>&1 | Out-Null
Say 'bcd attempted'

# safe mode ignores ACPI shutdown -> hard poweroff, then cold start
& $v controlvm $VM poweroff 2>&1 | Out-Null
Start-Sleep -Seconds 3
Say ("after_poweroff state={0}" -f (State))
& $v startvm $VM 2>&1 | Out-Null
Say ("after_startvm state={0}" -f (State))

for ($i = 1; $i -le 12; $i++) {
    Start-Sleep -Seconds 10
    $s = State
    & $v controlvm $VM screenshotpng (Join-Path $d ("p281_f{0}.png" -f $i)) 2>&1 | Out-Null
    $len = 0
    $p = Join-Path $d ("p281_f{0}.png" -f $i)
    if (Test-Path $p) { $len = (Get-Item $p).Length }
    Say ("f{0} state={1} bytes={2} ga={3}" -f $i, $s, $len, (Ga))
    if ($s -ne 'running') { break }
}
Say 'VERDICT: pass only if a late frame is a normal desktop (taskbar, >=60 KB) with ga>=1; black + fresh Id=41 = reset family back'
Say 'END'
