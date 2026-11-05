# p272i_verify.ps1 - post-reboot proof that Guest Additions is actually live after p272g.
# Read-only inside the guest (sc query / dir / ver round-trip). One variable: GA state after reboot.
# Every result goes to p272i.txt - terminal echo is unreliable on this host.
$VB   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM   = 'Win11-Test2'
$U    = 'vboxuser'
$P    = 'password'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$base = Join-Path $root '_ritual'
$log  = Join-Path $env:TEMP 'p272i.txt'
$gd   = 'C:\Users\Public\p272i'
function Say($t) { $s = (([string]$t) -replace "`0", '' -replace '[^\x20-\x7E\r\n]', ' ' -replace '\s+', ' '); if ($s.Length -gt 400) { $s = $s.Substring(0, 400) + '...[' + $s.Length + ']' }; ((Get-Date -f 'HH:mm:ss') + ' ' + $s) | Out-File -FilePath $log -Encoding utf8 -Append }
function S($t) { Say $t }
function Run([string[]]$a) { (& $VB @a 2>&1) -join "`r`n" }
function VGC([string[]]$a) { $o = Run (@('guestcontrol', $VM, '--username', $U, '--password', $P) + $a); return @{ rc = $LASTEXITCODE; o = $o } }
function Sh([string]$c) { $r = VGC @('run', '--exe', 'C:\Windows\System32\cmd.exe', '--wait-stdout', '--wait-stderr', '--timeout', '60000', '--', 'cmd.exe', '/c', $c); return $r }

S 'START p272i_verify'
$pre = Run @('showvminfo', $VM, '--machinereadable')
($pre -split "`r?`n") | Select-String '^(VMState|GuestAdditionsRunLevel)=' | ForEach-Object { Say ('pre ' + $_.Line) }
Say ('pre ver=' + (Run @('guestproperty', 'get', $VM, '/VirtualBox/GuestAdd/Version')))
Say ('pre sh=2.2.2 channels: prop=' + (Run @('guestproperty', 'enumerate', $VM) | Select-String 'GuestAdd' | Measure-Object).Count)

# 1 - core round-trip: can we run and does the guest answer with a marker?
$r1 = Sh ('echo MARK272I & ver')
Say ('run rc=' + $r1.rc + ' out=' + $r1.o)

# 2 - the four GA services
foreach ($svc in 'VBoxGuest', 'VBoxMouse', 'VBoxService', 'VBoxSF') {
    $r = Sh ('sc query ' + $svc + ' | findstr /i "SERVICE_NAME STATE"')
    Say ('svc ' + $svc + ' rc=' + $r.rc + ' out=' + $r.o)
}

# 3 - driver files on disk + their file versions (proves binaries landed from F:)
$r3 = Sh ('dir /b C:\Windows\System32\drivers\VBox*.sys 2>&1')
Say ('drvfiles rc=' + $r3.rc + ' out=' + $r3.o)
$r4 = Sh ('powershell -NoProfile -c "Get-ChildItem C:\Windows\System32\drivers\VBox*.sys | ForEach-Object { $_.Name + '' '' + $_.VersionInfo.FileVersion }"')
Say ('drvver rc=' + $r4.rc + ' out=' + $r4.o)

# 4 - copyto/copyfrom round-trip through the shared channel
$mk = Join-Path $base ('p272i_mark_' + (Get-Date -f 'HHmmss') + '.txt')
('p272i ' + (Get-Date -f 'HH:mm:ss')) | Set-Content -LiteralPath $mk -Encoding utf8
$ct = VGC @('copyto', '--target-directory', $gd, $mk)
Say ('copyto rc=' + $ct.rc + ' out=' + $ct.o)
$r5 = Sh ('if not exist ' + $gd + ' md ' + $gd + ' & dir /b ' + $gd)
Say ('dir rc=' + $r5.rc + ' out=' + $r5.o)
$cf = VGC @('copyfrom', ($gd + '\' + (Split-Path $mk -Leaf)), (Join-Path $base 'p272i_back.txt'))
Say ('copyfrom rc=' + $cf.rc + ' out=' + $cf.o + ' local=' + (Test-Path (Join-Path $base 'p272i_back.txt')))

# 5 - clip control (only works with live GA + session)
$r6 = Sh ('powershell -NoProfile -c "Set-Clipboard -Value MARK272I; Get-Clipboard"')
Say ('clip rc=' + $r6.rc + ' out=' + $r6.o)

$ok = ($r1.rc -eq 0) -and ($r1.o -match 'MARK272I') -and ($cf.rc -eq 0) -and (Test-Path (Join-Path $base 'p272i_back.txt'))
if ($ok) {
    Say 'RESULT: guestcontrol=PASS (run+copy round-trip) ga=live'
    Say 'VERDICT: variable=GA after p272g reboot result=RESTORED, diag can resume'
} else {
    Say 'RESULT: guestcontrol=FAIL'
    Say 'VERDICT: variable=GA after p272g reboot result=NOT restored, read svc/drv lines'
}
Say 'END'