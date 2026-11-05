# p275_boot.ps1 - probe #275 (variable: none - observation only; safeboot was armed by p274)
# p274 armed `bcdedit /set {default} safeboot minimal`, then the guest hard-reset (black frame).
# The next boot therefore has to come up in SAFE MODE, which is the stable bench for the GA
# install that follows (no EchoDrv/PCA dialog, no third-party drivers competing).
# Read-only: 24 frames @5s, nothing is typed, nothing is changed.
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$log = Join-Path $d 'p275.log'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $log -Encoding ascii -Append }
function State { (& $v showvminfo $VM --machinereadable | Select-String 'VMState="(\w+)"').Matches.Groups[1].Value }

Say ("start pre VMState={0}" -f (State))
for ($i = 1; $i -le 24; $i++) {
    Start-Sleep -Seconds 5
    $f = Join-Path $d ("p275_t{0}.png" -f $i)
    & $v controlvm $VM screenshotpng $f 2>&1 | Out-Null
    $sz = if (Test-Path $f) { (Get-Item $f).Length } else { 0 }
    Say ("t{0} state={1} size={2}" -f $i, (State), $sz)
}
Say 'RESULT: frames p275_t1..24'
Say 'VERDICT: safeboot held if a frame shows the black safe-mode desktop with corner text'
Say 'done'
