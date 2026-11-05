# p316_gcverify.ps1 - probe #316 (variable: durability of the working credential set from #315)
# #315 set the password as an elevated admin and got gc rc=0 AFTERRESET - the first successful logon in
# this whole line. One success is not a channel, so this probe runs it again on a different payload,
# then a NEGATIVE CONTROL (wrong password must still be refused), then reads Guest Additions state.
# Nothing is mutated; the VM is left running.
$d = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$out = Join-Path $d 'p316.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function GC([string]$pw, [string]$cmd) {
    $o = & $v guestcontrol $VM run --username vboxuser --password $pw --timeout 45000 --wait-stdout --wait-stderr --exe 'C:\Windows\System32\cmd.exe' -- cmd /c $cmd 2>&1
    return @{ rc = $LASTEXITCODE; o = (($o -join ' ') -replace '\s+', ' ') }
}
Say 'START'
Say ('state=' + (((& $v showvminfo $VM --machinereadable | Select-String '^VMState=') -replace '.*=', '') -replace '"', ''))
$r1 = GC 'vboxuser' 'whoami'
Say ('gc1 rc=' + $r1.rc + ' o=' + $r1.o)
$r2 = GC 'vboxuser' 'echo SECOND && ver'
Say ('gc2 rc=' + $r2.rc + ' o=' + $r2.o)
$r3 = GC 'WRONGPW' 'whoami'
Say ('gc_neg rc=' + $r3.rc + ' o=' + $r3.o)
$r4 = GC 'vboxuser' 'sc query vboxservice | findstr STATE'
Say ('gc_svc rc=' + $r4.rc + ' o=' + $r4.o)
$gp = & $v guestproperty enumerate $VM 2>&1 | Select-String 'VBoxGuest|VBoxService|GuestAdditionsRunLevel'
Say ('guestprops=' + (($gp | ForEach-Object { $_.Line.Trim() }) -join ' | '))
Say 'END'