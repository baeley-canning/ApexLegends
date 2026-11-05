# p272j_verify.ps1 - corrected post-reboot GA proof. Supersedes p272i, whose wrapper was broken:
#   1. helper was named GV, which is the built-in alias for Get-Variable (aliases outrank functions)
#   2. findstr "SERVICE_NAME STATE" lost its quotes through cmd.exe -> "Cannot open STATE"
#   3. the | inside a powershell -Command string was parsed by cmd.exe, not powershell
#   4. copyto ran before the target directory existed
# Single variable: GA live after the p272g reboot. Guest is read-only except the marker round-trip.
# Every result goes to p272j.txt - terminal echo on this host is unreliable.
$VB   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM   = 'Win11-Test2'
$U    = 'vboxuser'
$P    = 'password'
$base = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$log  = Join-Path $env:TEMP 'p272j.txt'
$gd   = 'C:\Users\Public\p272j'
function Say($t) { $s = (([string]$t) -replace "`0", '' -replace '[^\x20-\x7E\r\n]', ' ' -replace '\s+', ' '); if ($s.Length -gt 400) { $s = $s.Substring(0, 400) + '...[' + $s.Length + ']' }; ((Get-Date -f 'HH:mm:ss') + ' ' + $s) | Out-File -FilePath $log -Encoding utf8 -Append }
function Run([string[]]$a) { (& $VB @a 2>&1) -join "`r`n" }
function VGC([string[]]$a) { $o = Run (@('guestcontrol', $VM, '--username', $U, '--password', $P) + $a); return @{ rc = $LASTEXITCODE; o = $o } }
function Cmd([string]$c) { VGC @('run', '--exe', 'C:\Windows\System32\cmd.exe', '--wait-stdout', '--wait-stderr', '--timeout', '60000', '--', 'cmd.exe', '/c', $c) }
function PSG([string]$c) { VGC @('run', '--exe', 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe', '--wait-stdout', '--wait-stderr', '--timeout', '90000', '--', 'powershell.exe', '-NoProfile', '-Command', $c) }

Say 'START p272j_verify (corrected wrapper)'
$pre = Run @('showvminfo', $VM, '--machinereadable')
($pre -split "`r?`n") | Select-String '^(VMState|GuestAdditionsRunLevel)=' | ForEach-Object { Say ('pre ' + $_.Line) }
Say ('pre ver=' + (Run @('guestproperty', 'get', $VM, '/VirtualBox/GuestAdd/Version')))

# 1 - core round-trip: guest runs our command and answers with the marker
$r1 = Cmd 'echo MARK272J & ver'
Say ('run rc=' + $r1.rc + ' out=' + $r1.o)

# 2 - the four GA services, filtered locally so no quoting survives into cmd
foreach ($svc in 'VBoxGuest', 'VBoxMouse', 'VBoxService', 'VBoxSF') {
    $r = Cmd ('sc query ' + $svc)
    $keep = ($r.o -split "`r?`n") | Select-String 'SERVICE_NAME|STATE|FAILED' | ForEach-Object { $_.Line.Trim() }
    Say ('svc ' + $svc + ' rc=' + $r.rc + ' out=' + (($keep -join ' / ')))
}

# 3 - driver binaries on disk and their file versions (proves the payload from F: really landed)
$r3 = Cmd 'dir /b C:\Windows\System32\drivers\VBox*.sys'
Say ('drvfiles rc=' + $r3.rc + ' out=' + $r3.o)
$r4 = PSG '(Get-Item C:\Windows\System32\drivers\VBoxGuest.sys).VersionInfo.FileVersion'
Say ('drvver A rc=' + $r4.rc + ' out=' + $r4.o)
$r4b = Cmd 'powershell -NoProfile -Command "(gi C:\Windows\System32\drivers\VBoxWddm.sys).VersionInfo.FileVersion"'
Say ('drvver B rc=' + $r4b.rc + ' out=' + $r4b.o)

# 4 - copyto / copyfrom round-trip. Directory is created first, this time.
$r5 = Cmd ('if not exist ' + $gd + ' md ' + $gd + ' & if exist ' + $gd + ' echo DIRREADY')
Say ('mkdir rc=' + $r5.rc + ' out=' + $r5.o)
$name = 'p272j_mark_' + (Get-Date -f 'HHmmss') + '.txt'
$mk = Join-Path $env:TEMP $name
$back = Join-Path $env:TEMP 'p272j_back.txt'
Remove-Item -LiteralPath $back -Force -ErrorAction SilentlyContinue
('p272j ' + (Get-Date -f 'HH:mm:ss')) | Set-Content -LiteralPath $mk -Encoding utf8
$ct = VGC @('copyto', $mk, ($gd + '\' + $name))
Say ('copyto rc=' + $ct.rc + ' out=' + $ct.o)
$r6 = Cmd ('dir /b ' + $gd)
Say ('dir rc=' + $r6.rc + ' out=' + $r6.o)
$cf = VGC @('copyfrom', ($gd + '\' + $name), $back)
Say ('copyfrom rc=' + $cf.rc + ' out=' + $cf.o + ' local=' + (Test-Path -LiteralPath $back))

# 5 - clipboard needs a live session + live GA
$r7 = PSG 'Set-Clipboard -Value MARK272J; Get-Clipboard'
Say ('clip rc=' + $r7.rc + ' out=' + $r7.o)

$ok = ($r1.rc -eq 0) -and ($r1.o -match 'MARK272J') -and ($cf.rc -eq 0) -and (Test-Path -LiteralPath $back)
if ($ok) {
    Say 'RESULT: guestcontrol=PASS run+copy round-trip both rc=0, marker returned'
    Say 'VERDICT: variable=GA after p272g reboot result=RESTORED, p37 diag can resume'
} else {
    Say 'RESULT: guestcontrol=FAIL'
    Say 'VERDICT: variable=GA after p272g reboot result=NOT restored, read the svc/drv lines'
}
Say 'END'
