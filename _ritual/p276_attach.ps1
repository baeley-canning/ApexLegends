# p276_attach.ps1 - probe #276 (variable: GA ISO attached at SATA port 3)
# Facts: no GA bits exist on the guest disk, no GA ISO was attached, guest is now in SAFE MODE
# (p275_t4.png, "Safe Mode" corners). Safe mode is the stable bench: EchoDrv/PCA absent.
# Reversible: --medium none detaches again; safeboot stays armed for the next boot.
# Attach has to happen with the VM off (SATA hotplug off on this controller).
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$log = Join-Path $d 'p276.log'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $log -Encoding ascii -Append }
function State { (& $v showvminfo $VM --machinereadable | Select-String 'VMState="(\w+)"').Matches.Groups[1].Value }
function Store { (& $v showvminfo $VM --machinereadable | Select-String '"SATA-[0-9]-0"') -join ' | ' }

Say ("pre state={0} storage={1}" -f (State), (Store))
Say 'PRE-RECORDED above; restore = storageattach --port 3 --device 0 --type dvddrive --medium none'

# 1) graceful shutdown, hard poweroff only as fallback
& $v controlvm $VM acpi 2>&1 | Out-Null
for ($i = 0; $i -lt 20; $i++) { Start-Sleep -Seconds 3; if ((State) -eq 'poweroff') { break } }
$st = State
Say ("after acpi state={0}" -f $st)
if ($st -ne 'poweroff') { & $v controlvm $VM poweroff 2>&1 | Out-Null; Start-Sleep -Seconds 3; Say ("hard poweroff -> state={0}" -f (State)) }

# 2) attach GA ISO on the free port
& $v storageattach $VM --storagectl SATA --port 3 --device 0 --type dvddrive --medium additions 2>&1 | Out-File $log -Encoding ascii -Append
Say ("attach rc={0}" -f $LASTEXITCODE)
Say ("post storage={0}" -f (Store))

# 3) boot back up (safeboot still armed -> safe mode again)
& $v startvm $VM 2>&1 | Out-File $log -Encoding ascii -Append
Say ("startvm rc={0}" -f $LASTEXITCODE)

# 4) wait for the black safe-mode desktop (small PNG ~20-30 KB, stable over 3 frames)
$prev = 0; $same = 0
for ($i = 1; $i -le 40; $i++) {
    Start-Sleep -Seconds 5
    $f = Join-Path $d 'p276_wait.png'
    & $v controlvm $VM screenshotpng $f 2>&1 | Out-Null
    $sz = if (Test-Path $f) { (Get-Item $f).Length } else { 0 }
    if ($sz -gt 15000 -and $sz -lt 60000 -and [math]::Abs($sz - $prev) -lt 1500) { $same++ } else { $same = 0 }
    Say ("w{0} state={1} size={2} same={3}" -f $i, (State), $sz, $same)
    if ($same -ge 3) { break }
}
Copy-Item (Join-Path $d 'p276_wait.png') (Join-Path $d 'p276_desk.png') -Force
Say ("RESULT: state={0} iso_attached={1}" -f (State), ((Store) -match 'VBoxGuestAdditions|additions|VBoxGuest'))
Say 'VERDICT: safe-mode desktop back if p276_desk.png shows the black safe-mode wallpaper'
Say 'done'
