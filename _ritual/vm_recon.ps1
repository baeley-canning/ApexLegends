# vm_recon.ps1 - host side: push guest_recon.ps1 into the VM via guestcontrol, run it,
# pull the result back.  Proves the whole host<->guest automation channel works.
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$U  = 'vboxuser'
$P  = 'password'
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$o    = Join-Path $base 'vm_recon.txt'
function S($t) { $t | Out-File -FilePath $o -Encoding ascii -Append }
if (Test-Path $o) { Remove-Item $o -Force }
Remove-Item -Path 'Alias:gc' -Force -EA 0   # else the Get-Content alias wins over this function (alias > function)
function GC([string[]]$a) { (& $VB @a 2>&1) -join "`r`n" }

S ("vm_recon " + (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
S ("running: " + (GC @('list', 'runningvms')))
S ("ga status: " + (GC @('guestproperty', 'get', $VM, '/VirtualBox/GuestAdd/Version')))
S ("guest net: " + (GC @('guestproperty', 'get', $VM, '/VirtualBox/GuestInfo/Net/0/V4/IP')))

S '--- copyto guest_recon.ps1 + resmap.ps1 ---'
S (GC @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyto',
        '--target-directory', 'C:\Users\vboxuser', (Join-Path $base 'guest_recon.ps1')))
S (GC @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyto',
        '--target-directory', 'C:\Users\vboxuser', (Join-Path $base 'resmap.ps1')))

S '--- run recon in guest ---'
S (GC @('guestcontrol', $VM, '--username', $U, '--password', $P, 'run',
        '--exe', 'C:\Windows\System32\cmd.exe', '--wait-stdout', '--wait-stderr', '--',
        'cmd.exe', '/c', 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\vboxuser\guest_recon.ps1'))

S '--- copyfrom guest_recon.txt ---'
S (GC @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyfrom',
        'C:\Users\vboxuser\guest_recon.txt', (Join-Path $base 'vm_guest_recon.txt')))

if (Test-Path (Join-Path $base 'vm_guest_recon.txt')) {
    S '--- guest_recon.txt contents ---'
    S ((Get-Content (Join-Path $base 'vm_guest_recon.txt') -EA 0) -join "`r`n")
} else { S '(no guest_recon.txt pulled)' }
S '--- end ---'
