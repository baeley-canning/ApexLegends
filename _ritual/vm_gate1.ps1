# vm_gate1.ps1 - host side: push vm_gate1_probe.ps1 into the guest, run, pull back.
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$U  = 'vboxuser'
$P  = 'password'
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$o    = Join-Path $base 'vm_gate1.txt'
function Say($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
function Run([string[]]$a) { (& $VB @a 2>&1) -join "`r`n" }
if (Test-Path $o) { Remove-Item $o -Force }

Say ('vm_gate1 {0}' -f (Get-Date))
Say ('runningvms: ' + (Run @('list', 'runningvms')))
Say ('GA version: ' + (Run @('guestproperty', 'get', $VM, '/VirtualBox/GuestAdd/Version')))

Say '--- copyto probe ---'
Say (Run @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyto', '--target-directory', 'C:\Users\vboxuser', (Join-Path $base 'vm_gate1_probe.ps1')))

Say '--- run probe in guest ---'
Say (Run @('guestcontrol', $VM, '--username', $U, '--password', $P, 'run', '--exe', 'C:\Windows\System32\cmd.exe', '--wait-stdout', '--wait-stderr', '--timeout', '120000', '--',
           'cmd.exe', '/c', 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\vboxuser\vm_gate1_probe.ps1'))

$pull = Join-Path $base 'vm_gate1_probe_out.txt'
Say '--- copyfrom ---'
Say (Run @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyfrom', 'C:\Users\vboxuser\vm_gate1_probe.txt', $pull))
if (Test-Path $pull) { Say '--- guest output ---'; Say ((Get-Content $pull -EA 0) -join "`r`n") } else { Say '(no output pulled)' }
Say '--- end ---'
