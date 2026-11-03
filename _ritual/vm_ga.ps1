# vm_ga.ps1 - blind attempt to get Guest Additions into the VM using keystrokes only.
# Sequence: wake/unlock (autologon user vboxuser/password), Win+R, run the GA installer
# from the attached GA DVD, accept UAC, then poll the guest property channel.
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$VB   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM   = 'Win11-Test2'
$log  = Join-Path $base 'vm_ga.txt'
function Say($t) { $t | Out-File -FilePath $log -Encoding ascii -Append }
if (Test-Path $log) { Remove-Item $log -Force }

Say ("== vm_ga {0}" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
$t = Join-Path $base 'vm_type.ps1'

Say '--- wake + unlock ---'
& $t -Seq 'space'          ; Start-Sleep -Seconds 3
& $t -Seq 'password', 'enter'; Start-Sleep -Seconds 4

Say '--- run the guest additions installer from the attached GA iso ---'
& $t -Seq 'winr'                     ; Start-Sleep -Seconds 2
& $t -Seq 'd:\vboxwindowsadditions.exe /s' ; Start-Sleep -Seconds 2
& $t -Seq 'enter'                    ; Start-Sleep -Seconds 5
& $t -Seq 'alty'                     ; Start-Sleep -Seconds 3

Say '--- poll for GA (60 s) ---'
$ok = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 5
    $v = (& $VB guestproperty get $VM '/VirtualBox/GuestAdd/Version' 2>&1) -join ' '
    Say ("  t+{0}s : {1}" -f (5 * ($i + 1)), $v)
    if ($v -notmatch 'No value set') { $ok = $true; break }
}
Say ("GA published = " + $ok)
Say '--- end ---'
