# p272_arm.ps1 - probe #272 (variable: bcdedit safeboot, set from the LIVE desktop)
# Waits for the desktop (screenshot > threshold), then in ONE shell window:
#   1) bcdedit /set {default} safeboot minimal   -> persists across the crash/reset
#   2) sc query vboxservice                      -> pre-state read-back
#   3) sc start VBoxService                      -> GA arm attempt #2 (correct token form)
# Reversibility: safeboot is removed later by `bcdedit /deletevalue {default} safeboot`
# (p283). Safe to re-run: bcdedit /set is idempotent.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$log = Join-Path $d 'p272.log'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $log -Encoding ascii -Append }

function State { (& $v showvminfo $VM --machinereadable | Select-String 'VMState="(\w+)"').Matches.Groups[1].Value }
function Ga    { (& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=(\d)').Matches.Groups[1].Value }

Say 'start'
$pre = State
Say "pre VMState=$pre ga=$(Ga)"

# ---- phase 1: wait for the desktop, judged by screenshot size ----
$hit = 0
for ($i = 1; $i -le 40; $i++) {
    Start-Sleep -Seconds 6
    $shot = Join-Path $d 'p272_detect.png'
    & $v controlvm $VM screenshotpng $shot 2>&1 | Out-Null
    $sz = if (Test-Path $shot) { (Get-Item $shot).Length } else { 0 }
    Say ("detect {0} state={1} size={2}" -f $i, (State), $sz)
    if ($sz -gt 150000) { $hit = $i; break }
}
if ($hit -eq 0) { Say 'RESULT: no desktop detected in 240s'; Say 'VERDICT: FAIL'; return }

Say "desktop detected at detect#$hit - firing now"
& (Join-Path $d 'vm_type.ps1') -Seq @('winr')                                   | Out-Null
Start-Sleep -Milliseconds 600
& (Join-Path $d 'vm_type.ps1') -Seq @('cmd', 'enter')                            | Out-Null
Start-Sleep -Milliseconds 1800
# full bcdedit first: it must land before the reset
& (Join-Path $d 'vm_type.ps1') -Seq @('bcdedit /set {default} safeboot minimal', 'enter') | Out-Null
Start-Sleep -Milliseconds 1200
& $v controlvm $VM screenshotpng (Join-Path $d 'p272_bcd.png') | Out-Null
Say 'bcdedit typed'
& (Join-Path $d 'vm_type.ps1') -Seq @('sc start VBoxService', 'enter')            | Out-Null
Start-Sleep -Milliseconds 1500
& $v controlvm $VM screenshotpng (Join-Path $d 'p272_sc.png') | Out-Null
Say "post-arm ga=$(Ga)"

# ---- phase 2: 5 ticks of read-back ----
$ok = 0
for ($t = 1; $t -le 5; $t++) {
    Start-Sleep -Seconds 3
    $g = Ga
    Say ("tick {0} state={1} ga={2}" -f $t, (State), $g)
    if ($g -ge 1) { $ok++ }
}
Say ("RESULT: safeboot typed=$(Test-Path (Join-Path $d 'p272_bcd.png')); ga ticks>=1: {0}/5" -f $ok)
Say 'VERDICT: see p272_bcd.png / p272_sc.png (safe-mode persist is judged on the NEXT boot)'
Say 'done'
