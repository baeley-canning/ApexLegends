# vm_coldboot.ps1 - power off (dropping the saved state), discard it, cold boot headless,
# then take periodic framebuffer screenshots so we can SEE where the guest is.
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$log = Join-Path $base 'vm_coldboot.txt'
function Say($t) { $t | Out-File -FilePath $log -Encoding ascii -Append }
if (Test-Path $log) { Remove-Item $log -Force }

Say ("== vm_coldboot {0}" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'))
Say ("state before: " + ((& $VB showvminfo $VM --machinereadable 2>&1 | Select-String '^VMState') -join ' '))

Say '--- poweroff ---'
Say ((& $VB controlvm $VM poweroff 2>&1) -join "`r`n")
Start-Sleep -Seconds 3
Say ("state after poweroff: " + ((& $VB showvminfo $VM --machinereadable 2>&1 | Select-String '^VMState') -join ' '))

Say '--- discardstate ---'
Say ((& $VB discardstate $VM 2>&1) -join "`r`n")

Say '--- startvm headless (cold boot) ---'
Say ((& $VB startvm $VM --type headless 2>&1) -join "`r`n")

Say '--- screenshots at 15s intervals ---'
for ($i = 1; $i -le 6; $i++) {
    Start-Sleep -Seconds 15
    $png = Join-Path $base ("vmshot_{0}.png" -f $i)
    if (Test-Path $png) { Remove-Item $png -Force }
    $r = (& $VB controlvm $VM screenshotpng $png 2>&1) -join ' '
    Say ("  t+{0}s png={1} {2}" -f (15 * $i), (Test-Path $png), ($r -replace '\s+', ' '))
    if (Test-Path $png) { break }
}
Say ("GA: " + (((& $VB guestproperty get $VM '/VirtualBox/GuestAdd/Version' 2>&1)) -join ' '))
Say '--- end ---'
