# p322_locked.ps1 - probe #322 (variable: does guestcontrol work while the interactive session is LOCKED)
# The guest auto-locked at 10:42 right after p320/p321, which is the exact condition the retired
# keyboard path could never handle without a click+password. If gc still returns output here, the
# channel is session-independent and every future probe can ignore the desktop/lock state entirely.
# Read-only. The negative control is the state line itself: a locked session must not change the answer.
$d  = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p322.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function GCrun([string]$cmd) {
    $o = & $v guestcontrol $VM run --username vboxuser --password vboxuser --timeout 45000 --wait-stdout --wait-stderr --exe 'C:\Windows\System32\cmd.exe' -- cmd /c $cmd 2>&1
    $rc = $LASTEXITCODE
    return @{ rc = $rc; o = (($o -join ' ') -replace '\s+', ' ') }
}
Say 'START'
Say ('state=' + (((& $v showvminfo $VM --machinereadable | Select-String '^VMState=') -replace '.*=', '') -replace '"', ''))
$a = GCrun 'whoami'
Say ('locked_gc rc=' + $a.rc + ' o=' + $a.o)
$b = GCrun 'sc query vboxservice | findstr STATE'
Say ('locked_svc rc=' + $b.rc + ' o=' + $b.o)
$c = GCrun 'query session'
Say ('sessions rc=' + $c.rc + ' o=' + $c.o.Substring(0, [Math]::Min(300, $c.o.Length)))
Say 'VERDICT: locked_gc rc=0 means the channel is independent of the interactive session (keyboard path redundant)'
Say 'END'