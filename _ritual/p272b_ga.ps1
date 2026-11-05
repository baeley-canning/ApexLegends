# p272b - corrected GA install route. p272 typed into the Start search box ("winr" released Win before R),
# so Enter opened Bing instead of the installer. This version navigates Start -> "run" -> Enter -> Run
# dialog, then types the letter-agnostic launch there. Verdict only from the guest property channel.
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$VB   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM   = 'Win11-Test2'
$U    = 'vboxuser'
$P    = 'password'
$log  = Join-Path $base 'p272b_ga.log'
function L($s) { Add-Content -LiteralPath $log -Value ((Get-Date -f 'HH:mm:ss') + ' ' + $s) }
function Run([string[]]$a) { (& $VB @a 2>&1) -join "`r`n" }
function Rl { ((Run @('showvminfo', $VM, '--machinereadable')) -split "`r?`n" | Where-Object { $_ -match '^GuestAdditionsRunLevel=' }) }
$t = Join-Path $base 'vm_type.ps1'
$shot = Join-Path $base 'shot.ps1'
function T([string[]]$s) { & powershell -NoProfile -ExecutionPolicy Bypass -File $t -Seq $s }
function Shot($n) { & powershell -NoProfile -ExecutionPolicy Bypass -File $shot $n | Out-Null; L ('shot ' + $n) }
if (Test-Path $log) { Remove-Item $log -Force }

L 'start'
L ('pre GA version: ' + (Run @('guestproperty', 'get', $VM, '/VirtualBox/GuestAdd/Version')).Trim())
L ('pre runlevel: ' + (Rl))

Shot 'p272b_0'
L 'open Start, then search "run"'
T 'win'; Start-Sleep -Seconds 2; Shot 'p272b_1'
T 'run'; Start-Sleep -Seconds 1; Shot 'p272b_2'
T 'enter'; Start-Sleep -Seconds 2; Shot 'p272b_3'
L 'type the launcher into the Run dialog'
T 'cmd /c for %d in (d e f g h) do if exist %d:\vboxwindowsadditions.exe start "" %d:\vboxwindowsadditions.exe /s'
Start-Sleep -Seconds 1
T 'enter'; Start-Sleep -Seconds 6; Shot 'p272b_4'
T 'alty'; L 'alty sent (UAC accept)'

$up = $false
for ($i = 0; $i -lt 36; $i++) {
  Start-Sleep -Seconds 5
  $v = (Run @('guestproperty', 'get', $VM, '/VirtualBox/GuestAdd/Version')).Trim()
  L ('  t+{0}s GA={1} {2}' -f (5 * ($i + 1)), $v, (Rl))
  if ($i -eq 5)  { Shot 'p272b_5' }
  if ($i -eq 12) { Shot 'p272b_6' }
  if ($i -eq 24) {
    # nothing after 2 min: re-send the launcher once (Run dialog may have taken it into the wrong field)
    L 'retry: reopen Start search route'
    T 'win'; Start-Sleep -Seconds 2; T 'run'; Start-Sleep -Seconds 1; T 'enter'; Start-Sleep -Seconds 2
    T 'cmd /c for %d in (d e f g h) do if exist %d:\vboxwindowsadditions.exe start "" %d:\vboxwindowsadditions.exe /s'
    Start-Sleep -Seconds 1; T 'enter'; Start-Sleep -Seconds 5; T 'alty'
    Shot 'p272b_7'
  }
  if ($v -notmatch 'No value set|error') { $up = $true; break }
}
Shot 'p272b_8'
L ('GA published = ' + $up)
if (-not $up) {
  L 'VERDICT p272b: FAIL - GA still not published'
  L 'RESULT p272b: read p272b_0..p272b_8; the desktop shows where the keystrokes landed.'
  exit 1
}

Start-Sleep -Seconds 15
$q = Run @('guestcontrol', $VM, '--username', $U, '--password', $P, '--wait-stdout', '--wait-exit', 'run',
           '--exe', 'C:\Windows\System32\cmd.exe', '--', 'cmd', '/c',
           'sc query vboxguest & sc query vboxservice & echo ga_up:P272B %DATE% %TIME% > C:\ga_up.txt')
L ('sc query: ' + $q)
$cf = Run @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyfrom', '--target-directory', $base, 'C:\ga_up.txt')
L ('copyfrom rc=' + $LASTEXITCODE + ' :: ' + $cf)
if ((Test-Path (Join-Path $base 'ga_up.txt')) -and $q -match 'RUNNING') {
  L 'VERDICT p272b: PASS - GA running, vboxguest+vboxservice RUNNING, copyfrom landed'
  L ('ga_up: ' + ((Get-Content (Join-Path $base 'ga_up.txt') -Raw) -replace "`r?`n", ' '))
} else {
  L 'VERDICT p272b: PARTIAL - GA published but service/copyfrom proof incomplete'
}
L 'RESULT p272b: done'
