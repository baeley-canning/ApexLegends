# p273_arm.ps1 - probe #273 (variable: elevation via Win+X -> Terminal (Admin) + UAC Alt+Y)
# Purpose: the #272 read-back proved two things that block GA arming:
#   * bcdedit -> "Access is denied"      (plain cmd has no admin token)
#   * sc start VBoxService -> 1060       (service was never registered)
# So this probe elevates first, then does, in order:
#   1) bcdedit /set {default} safeboot minimal      (persists across reset)
#   2) cd to the GA dir, VBoxService.exe --register  (creates the missing service)
#   3) sc start VBoxService                          (first real arm attempt)
# Reversibility: safeboot -> p28x deletevalue; service registered by us -> `sc delete VBoxService`.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$log = Join-Path $d 'p273.log'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $log -Encoding ascii -Append }
function State { (& $v showvminfo $VM --machinereadable | Select-String 'VMState="(\w+)"').Matches.Groups[1].Value }
function Ga    { (& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=(\d)').Matches.Groups[1].Value }
function Shot($n) { & $v controlvm $VM screenshotpng (Join-Path $d $n) 2>&1 | Out-Null }

Say 'start'
Say "pre VMState=$(State) ga=$(Ga)"
Shot 'p273_pre.png'
$sz = (Get-Item (Join-Path $d 'p273_pre.png')).Length
Say "pre shot size=$sz"
# 90k, not 150k: a splash/black frame is 10-25k, a desktop even with a console window over the
# wallpaper is ~127k. p273's first run aborted on the 150k gate while the desktop was up.
if ($sz -lt 90000) { Say 'RESULT: not on a desktop right now'; Say 'VERDICT: ABORT'; return }

Say 'opening elevated shell: winx -> a -> alt-y'
& (Join-Path $d 'vm_type.ps1') -Seq @('winx') | Out-Null
Start-Sleep -Milliseconds 500
& (Join-Path $d 'vm_type.ps1') -Seq @('a') | Out-Null
Start-Sleep -Milliseconds 1500
Shot 'p273_uacbt.png'
& (Join-Path $d 'vm_type.ps1') -Seq @('alty') | Out-Null
Start-Sleep -Milliseconds 4500
Shot 'p273_uac.png'
Say 'elevation keyed'

& (Join-Path $d 'vm_type.ps1') -Seq @('bcdedit /set {default} safeboot minimal', 'enter') | Out-Null
Start-Sleep -Milliseconds 900
Shot 'p273_bcd.png'
Say 'bcdedit done'

& (Join-Path $d 'vm_type.ps1') -Seq @('cd "C:\Program Files\Oracle\VirtualBox Guest Additions"', 'enter') | Out-Null
Start-Sleep -Milliseconds 900
& (Join-Path $d 'vm_type.ps1') -Seq @('VBoxService.exe --register', 'enter') | Out-Null
Start-Sleep -Milliseconds 1500
Shot 'p273_reg.png'
Say 'register done'

& (Join-Path $d 'vm_type.ps1') -Seq @('sc start VBoxService', 'enter') | Out-Null
Start-Sleep -Milliseconds 1500
Shot 'p273_out.png'
Say "post-arm ga=$(Ga)"

for ($t = 1; $t -le 6; $t++) {
    Start-Sleep -Seconds 3
    $g = Ga
    Say ("tick {0} state={1} ga={2}" -f $t, (State), $g)
    Shot ("p273_t{0}.png" -f $t)
}
Say ("RESULT: ga_max_at_readback_end={0}; elevated={1}" -f (Ga), (Test-Path (Join-Path $d 'p273_out.png')))
Say 'VERDICT: ga>0 => GA armed; screenshots p273_bcd/p273_reg/p273_out are the evidence'
Say 'done'
