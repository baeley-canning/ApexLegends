# h260_vm_apc.ps1 - VM bench for the v3 APC inject rung (R1: driver change runs in the VM first).
# Restores Win11-Test2 to p37-ready (gdrv3 + harness present), pushes the three artifacts,
# loads apexdrv with kdu DSE-off, injects into notepad.exe via --method=kernel, pulls the log,
# then RESTORES the snapshot (R4). Every step appended to h260_vm.txt - terminal output is unreliable.
$VB  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$SNAP= 'p37-ready'
$U   = 'vboxuser'
$P   = 'password'
$root= 'C:\Users\New User\OneDrive\Desktop\cheating'
$base= Join-Path $root '_ritual'
$log = Join-Path $base 'h260_vm.txt'
function Say($t) { ((Get-Date -f 'HH:mm:ss') + ' ' + $t) | Out-File -FilePath $log -Encoding utf8 -Append }
function Run([string[]]$a) { (& $VB @a 2>&1) -join "`r`n" }

if (Test-Path $log) { Remove-Item $log -Force }
Say "START - bench of apexdrv v3 (APC inject) on $VM"

Say ('restore: ' + (Run @('snapshot', $VM, 'restore', $SNAP)))
Say ('start: '   + (Run @('startvm', $VM, '--type', 'headless')))

# wait for Guest Additions control channel
$up = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 5
    $v = Run @('guestproperty', 'get', $VM, '/VirtualBox/GuestAdd/Version')
    if ($v -notmatch 'No value set') { $up = $true; Say ('GA up after ' + (($i + 1) * 5) + 's: ' + $v.Trim()); break }
}
if (-not $up) { Say 'RESULT: FAIL guest additions never came up'; exit 1 }
Start-Sleep -Seconds 20    # let the desktop settle

$bld = Join-Path $root 'QwenKernPremium\build'
Say '--- copy artifacts ---'
foreach ($f in @('apexdrv.sys', 'apex_launcher.exe', 'apexcheat.dll')) {
    Say ($f + ': ' + (Run @('guestcontrol', $VM, '--username', $U, '--password', $P,
                            'copyto', '--target-directory', 'C:\Users\vboxuser',
                            (Join-Path $bld $f))))
}

$probe = Join-Path $base 'h260_vm_probe.ps1'
Say '--- copy guest script ---'
Say (Run @('guestcontrol', $VM, '--username', $U, '--password', $P,
           'copyto', '--target-directory', 'C:\Users\vboxuser', $probe))

Say '--- run in guest ---'
Say (Run @('guestcontrol', $VM, '--username', $U, '--password', $P,
           'run', '--exe', 'C:\Windows\System32\cmd.exe', '--wait-stdout', '--wait-stderr',
           '--timeout', '240000', '--',
           'cmd.exe', '/c', 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\vboxuser\h260_vm_probe.ps1'))

$pull = Join-Path $base 'h260_guest_out.txt'
Say '--- copyfrom guest log ---'
Say (Run @('guestcontrol', $VM, '--username', $U, '--password', $P,
           'copyfrom', 'C:\Users\vboxuser\h260_probe.txt', $pull))
if (Test-Path $pull) { Say '--- guest output ---'; Say ((Get-Content $pull -EA 0) -join "`r`n") } else { Say '(no guest output pulled)' }

Say ('RESULT: done - restoring snapshot')
Say ('restore back: ' + (Run @('snapshot', $VM, 'restore', $SNAP)))
Say 'END'
