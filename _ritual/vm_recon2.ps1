# vm_recon2.ps1 - host side, no alias collisions (function named Run, not GC).
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$U  = 'vboxuser'
$P  = 'password'
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$o    = Join-Path $base 'vm_recon2.txt'
function Say($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
function Run([string[]]$a) { (& $VB @a 2>&1) -join "`r`n" }
if (Test-Path $o) { Remove-Item $o -Force }

Say ("vm_recon2 {0}" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
Say ("aliases: gc=" + (Get-Alias gc -EA 0).Definition + " s=" + (Get-Alias s -EA 0).Definition)
Say ("runningvms: " + (Run @('list', 'runningvms')))
Say ("GA version: " + (Run @('guestproperty', 'get', $VM, '/VirtualBox/GuestAdd/Version')))
Say ("guest OS   : " + (Run @('guestproperty', 'get', $VM, '/VirtualBox/GuestInfo/OS/Product')))
Say ("guest net  : " + (Run @('guestproperty', 'get', $VM, '/VirtualBox/GuestInfo/Net/0/V4/IP')))

Say '--- copyto ---'
Say ("recon: " + (Run @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyto', '--target-directory', 'C:\Users\vboxuser', (Join-Path $base 'guest_recon.ps1'))))
Say ("resmap: " + (Run @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyto', '--target-directory', 'C:\Users\vboxuser', (Join-Path $base 'resmap.ps1'))))

Say '--- run recon in guest ---'
Say (Run @('guestcontrol', $VM, '--username', $U, '--password', $P, 'run', '--exe', 'C:\Windows\System32\cmd.exe', '--wait-stdout', '--wait-stderr', '--',
           'cmd.exe', '/c', 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\vboxuser\guest_recon.ps1'))

$pull = Join-Path $base 'vm_guest_recon.txt'
Say '--- copyfrom ---'
Say (Run @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyfrom', 'C:\Users\vboxuser\guest_recon.txt', $pull))
if (Test-Path $pull) { Say '--- guest_recon.txt ---'; Say ((Get-Content $pull -EA 0) -join "`r`n") }
Say '--- end ---'
