# p299_reboot.ps1 - probe #299 (variable: reboot with safeboot verified absent immediately before)
# #298 cleared safeboot on {current} and the in-guest read-back was empty. Re-read once right before
# the poweroff to catch a re-arm, then boot normal and watch 12 frames. GA is installed (p280), so
# ga>=1 plus a blue desktop with no "Safe Mode" corner text is the pass condition.
# FIXED after #314: this used to start with `--type headless`, and on Windows a UI cannot be attached
# to a headless session afterwards - every post-reboot click was a silent no-op. It now starts the
# VirtualBoxVM.exe frontend so the console window exists and ensure_ui.ps1 can also repair it later.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VV  = 'C:\Program Files\Oracle\VirtualBox\VirtualBoxVM.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p299.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function K([string[]]$s) { & (Join-Path $d 'vm_type.ps1') -Seq $s | Out-Null }
Say 'START'
K @('esc'); Start-Sleep -Milliseconds 500
K @("bcdedit /enum '{current}' | sls safeboot"); Start-Sleep -Milliseconds 400
K @('enter'); Start-Sleep -Seconds 4
& $v controlvm $VM screenshotpng (Join-Path $d 'p299_pre.png') 2>&1 | Out-Null
Say 'shot pre'
& $v controlvm $VM poweroff 2>&1 | Out-Null
Start-Sleep -Seconds 4
Say ('after_poweroff state=' + (((& $v showvminfo $VM --machinereadable | Select-String 'VMState=') -replace 'VMState="', '') -replace '"', ''))
Start-Process $VV -ArgumentList '--startvm', $VM
Start-Sleep -Seconds 6
Say ('after_startvm state=' + (((& $v showvminfo $VM --machinereadable | Select-String 'VMState=') -replace 'VMState="', '') -replace '"', ''))
for ($i = 1; $i -le 12; $i++) {
    Start-Sleep -Seconds 10
    $png = Join-Path $d ('p299_f{0}.png' -f $i)
    & $v controlvm $VM screenshotpng $png 2>&1 | Out-Null
    $st = ((& $v showvminfo $VM --machinereadable | Select-String 'VMState=') -replace 'VMState="', '') -replace '"', ''
    $ga = ((& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=') -replace '.*=', '')
    $b = 0; if (Test-Path $png) { $b = (Get-Item $png).Length }
    Say ('f{0} state={1} bytes={2} ga={3}' -f $i, $st, $b, $ga)
}
Say 'VERDICT: pass if state stays running, ga>=1 and the last frames show a desktop without the Safe Mode corner text'
Say 'END'