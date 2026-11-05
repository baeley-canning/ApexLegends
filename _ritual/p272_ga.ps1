# p272_ga.ps1 - reinstall Guest Additions over scancodes only (guestcontrol is dead until GA is back).
# Letter-agnostic: the GA DVD letter changed (was F: on the 7.2.22 ISO), so probe D..H for the installer.
# Reversible: GA install is additive; snapshot pre-h268 stays the rollback point. Detached + logged.
# VERDICT is only ever taken from the guest property channel / guestcontrol, never from a keystroke.
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$VB   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM   = 'Win11-Test2'
$U    = 'vboxuser'
$P    = 'password'
$log  = Join-Path $base 'p272_ga.log'
function L($s) { Add-Content -LiteralPath $log -Value ((Get-Date -f 'HH:mm:ss') + ' ' + $s) }
function Run([string[]]$a) { (& $VB @a 2>&1) -join "`r`n" }
$t = Join-Path $base 'vm_type.ps1'
$shot = Join-Path $base 'shot.ps1'
if (Test-Path $log) { Remove-Item $log -Force }

L 'start'
$pre = (Run @('guestproperty', 'get', $VM, '/VirtualBox/GuestAdd/Version')).Trim()
L ('pre GA version: ' + $pre)
L ('pre runlevel: ' + (Run @('showvminfo', $VM, '--machinereadable') | Select-String 'GuestAdditionsRunLevel').ToString().Trim())

# session must be foreground + unlocked; wake with space, no password unless a lock screen answers
& powershell -NoProfile -ExecutionPolicy Bypass -File $shot 'p272_0' | Out-Null
L 'shot p272_0 (pre)'
& powershell -NoProfile -ExecutionPolicy Bypass -File $t -Seq 'space'; Start-Sleep -Seconds 2
& powershell -NoProfile -ExecutionPolicy Bypass -File $t -Seq 'password', 'enter'; Start-Sleep -Seconds 3
& powershell -NoProfile -ExecutionPolicy Bypass -File $shot 'p272_1' | Out-Null
L 'shot p272_1 (after wake/unlock attempt)'

L 'run dialog + letter-agnostic installer launch'
& powershell -NoProfile -ExecutionPolicy Bypass -File $t -Seq 'winr'; Start-Sleep -Seconds 2
& powershell -NoProfile -ExecutionPolicy Bypass -File $shot 'p272_2' | Out-Null
L 'shot p272_2 (run dialog)'
& powershell -NoProfile -ExecutionPolicy Bypass -File $t -Seq 'cmd /c for %d in (d e f g h) do if exist %d:\vboxwindowsadditions.exe start "" %d:\vboxwindowsadditions.exe /s'
Start-Sleep -Seconds 1
& powershell -NoProfile -ExecutionPolicy Bypass -File $t -Seq 'enter'
Start-Sleep -Seconds 6
& powershell -NoProfile -ExecutionPolicy Bypass -File $shot 'p272_3' | Out-Null
L 'shot p272_3 (post-enter, expect consent/UAC)'
& powershell -NoProfile -ExecutionPolicy Bypass -File $t -Seq 'alty'
L 'alty sent (UAC accept)'

# poll the property channel - this is the only verdict source
$up = $false
for ($i = 0; $i -lt 36; $i++) {
  Start-Sleep -Seconds 5
  $v = (Run @('guestproperty', 'get', $VM, '/VirtualBox/GuestAdd/Version')).Trim()
  $rl = (Run @('showvminfo', $VM, '--machinereadable') | Select-String 'GuestAdditionsRunLevel').ToString().Trim()
  L ('  t+{0}s GA={1} {2}' -f (5 * ($i + 1)), $v, $rl)
  if ($i -eq 3) { & powershell -NoProfile -ExecutionPolicy Bypass -File $shot 'p272_4' | Out-Null; L 'shot p272_4' }
  if ($i -eq 11) { & powershell -NoProfile -ExecutionPolicy Bypass -File $shot 'p272_5' | Out-Null; L 'shot p272_5' }
  if ($v -notmatch 'No value set|error') { $up = $true; break }
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $shot 'p272_6' | Out-Null
L 'shot p272_6 (final)'
L ('GA published = ' + $up)
if (-not $up) {
  L 'VERDICT p272: FAIL - GA never published a version; the guest stayed GA-less'
  L 'RESULT p272: no guestcontrol. Next: read p272_3..p272_6, then snapshot restore pre-h268.'
  exit 1
}

# hard proof: service state + a marker file written by the guest and copied back
Start-Sleep -Seconds 15
$q = Run @('guestcontrol', $VM, '--username', $U, '--password', $P, '--wait-stdout', '--wait-exit', 'run',
           '--exe', 'C:\Windows\System32\cmd.exe', '--', 'cmd', '/c',
           'sc query vboxguest & sc query vboxservice & echo ga_up:P272 %DATE% %TIME% > C:\ga_up.txt & type C:\ga_up.txt')
L ('sc query: ' + $q)
$cf = Run @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyfrom', '--target-directory', $base, 'C:\ga_up.txt')
L ('copyfrom rc=' + $LASTEXITCODE + ' :: ' + $cf)
if ((Test-Path (Join-Path $base 'ga_up.txt')) -and $q -match 'RUNNING') {
  L 'VERDICT p272: PASS - GA running, vboxguest/vboxservice RUNNING, guestcontrol copyfrom landed'
  L ('ga_up: ' + (Get-Content (Join-Path $base 'ga_up.txt') -Raw))
} else {
  L 'VERDICT p272: PARTIAL - GA published but service/`copyfrom` proof incomplete; read the log lines above'
}
L 'RESULT p272: done'
