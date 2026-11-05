# p272d - launch the GA installer directly off F: (p272c proved vboxwindowsadditions.exe exists at F:\).
# p272b's `for` loop matched too, but the silent install never surfaced -> go straight at the path here.
# T calls vm_type.ps1 IN-PROCESS: `powershell -File ... -Seq a,b,c` collapses tokens into one string.
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$VB   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM   = 'Win11-Test2'
$U    = 'vboxuser'
$P    = 'password'
$log  = Join-Path $base 'p272d_ga.log'
$shot = Join-Path $base 'shot.ps1'
$vt   = Join-Path $base 'vm_type.ps1'
function L($s) { Add-Content -LiteralPath $log -Value ((Get-Date -f 'HH:mm:ss') + ' ' + $s) }
function Run([string[]]$a) { (& $VB @a 2>&1) -join "`r`n" }
function Rl { ((Run @('showvminfo', $VM, '--machinereadable')) -split "`r?`n" | Where-Object { $_ -match '^GuestAdditionsRunLevel=' }) }
function T([string[]]$s) { & $vt -Seq $s }
function Shot($n) { & powershell -NoProfile -ExecutionPolicy Bypass -File $shot $n | Out-Null; L ('shot ' + $n) }
if (Test-Path $log) { Remove-Item $log -Force }

L 'start'
L ('pre GA version: ' + (Run @('guestproperty', 'get', $VM, '/VirtualBox/GuestAdd/Version')).Trim())
L ('pre runlevel: ' + (Rl))
Shot 'p272d_0'
L 'type F:\vboxwindowsadditions.exe /s into the focused cmd'
T 'F:\vboxwindowsadditions.exe /s'
Start-Sleep -Seconds 1
T 'enter'
Start-Sleep -Seconds 5
Shot 'p272d_1'
T 'alty'; L 'alty sent (UAC accept)'
Start-Sleep -Seconds 12
Shot 'p272d_2'

$up = $false
for ($i = 0; $i -lt 34; $i++) {
  Start-Sleep -Seconds 5
  $v = (Run @('guestproperty', 'get', $VM, '/VirtualBox/GuestAdd/Version')).Trim()
  L ('  t+{0}s GA={1} {2}' -f (17 + 5 * ($i + 1)), $v, (Rl))
  if ($i -eq 5)  { T 'alty'; Shot 'p272d_3' }
  if ($i -eq 14) { Shot 'p272d_4' }
  if ($i -eq 26) { Shot 'p272d_5' }
  if ($v -notmatch 'No value set|error') { $up = $true; break }
}
Shot 'p272d_6'
L ('GA published = ' + $up)
if (-not $up) {
  L 'VERDICT p272d: FAIL - GA still not published'
  L 'RESULT p272d: read p272d_0..p272d_6; check for a UAC window or an installer error page.'
  exit 1
}

Start-Sleep -Seconds 15
$q = Run @('guestcontrol', $VM, '--username', $U, '--password', $P, '--wait-stdout', '--wait-exit', 'run',
           '--exe', 'C:\Windows\System32\cmd.exe', '--', 'cmd', '/c',
           'sc query vboxguest & sc query vboxservice & echo ga_up:P272D %DATE% %TIME% > C:\ga_up.txt')
L ('sc query: ' + $q)
$cf = Run @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyfrom', '--target-directory', $base, 'C:\ga_up.txt')
L ('copyfrom rc=' + $LASTEXITCODE + ' :: ' + $cf)
if ((Test-Path (Join-Path $base 'ga_up.txt')) -and $q -match 'RUNNING') {
  L 'VERDICT p272d: PASS - GA running, vboxguest+vboxservice RUNNING, copyfrom landed'
  L ('ga_up: ' + ((Get-Content (Join-Path $base 'ga_up.txt') -Raw) -replace "`r?`n", ' '))
} else {
  L 'VERDICT p272d: PARTIAL - GA published but service/copyfrom proof incomplete'
}
L 'RESULT p272d: done'
