# p269_up.ps1 - VM-only recovery: record the wedged state, reset the VM, wait until guestcontrol
# actually answers (rc=0), and prove the channel with a file round-trip.
# Reversible: snapshot pre-h268 is the rollback point. No host reboot.
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM = 'Win11-Test2'; $U = 'vboxuser'; $P = 'password'
$b = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$log = Join-Path $b 'p269_up.txt'
$g = 'C:\Users\Public\p37'
function S($t) { ((Get-Date -f 'HH:mm:ss') + ' ' + (([string]$t) -replace "`0", '' -replace '[^\x20-\x7E]', ' ' -replace '\s+', ' ')) | Out-File -FilePath $log -Encoding utf8 -Append }
function V([string[]]$a) { $o = (& $VB @a 2>&1) | ForEach-Object { [string]$_ }; $r = $LASTEXITCODE; return @{ rc = $r; o = $o } }
function Sh([string]$c) { $x = V @('guestcontrol', $VM, '--username', $U, '--password', $P, 'run', '--exe', 'C:\Windows\System32\cmd.exe', '--wait-stdout', '--timeout', '30000', '--', 'cmd.exe', '/c', $c); S ('  sh rc=' + $x.rc + ' out=' + ($x.o -join ' | ')); return $x.rc }

S 'START p269_up'
$pre = V @('showvminfo', $VM, '--machinereadable')
$pre.o | Select-String 'VMState=|VMStateChangeTime|GuestAdditionsRunLevel' | ForEach-Object { S ('pre ' + $_.Line) }
S ('pre snapshot=' + ((V @('snapshot', $VM, 'list')).o | Select-String 'pre-h268' | ForEach-Object { $_.Line.Trim() }))

$r = V @('controlvm', $VM, 'reset')
S ('RESET rc=' + $r.rc + ' ' + ($r.o -join ' | '))

$up = $false
for ($i = 1; $i -le 40; $i++) {
    Start-Sleep -Seconds 10
    $st = ((V @('showvminfo', $VM, '--machinereadable')).o | Select-String 'VMState=' | ForEach-Object { $_.Line.Trim() })
    $lv = ((V @('showvminfo', $VM, '--machinereadable')).o | Select-String 'GuestAdditionsRunLevel' | ForEach-Object { $_.Line.Trim() })
    $rc = Sh ('echo up> ' + $g + '\ga_up.txt & echo P269OK')
    S ('try ' + $i + ' state=' + $st + ' ' + $lv + ' rc=' + $rc)
    if ($rc -eq 0) { $up = $true; break }
}
if ($up) {
    S ('ga_up: ' + (Sh ('dir /b ' + $g)))
    $cf = V @('guestcontrol', $VM, '--username', $U, '--password', $P, 'copyfrom', ($g + '\ga_up.txt'), (Join-Path $b 'p269_up_guest.txt'))
    S ('copyfrom rc=' + $cf.rc + ' local=' + (Test-Path (Join-Path $b 'p269_up_guest.txt')))
    S 'RESULT: channel=UP after reset'
    S 'VERDICT: variable=guest liveness (reset) result=channel restored, diag can run'
} else {
    S 'RESULT: channel=STILL DEAD after reset + 400s'
    S 'VERDICT: variable=guest liveness (reset) result=needs deeper look (GA install / safe mode)'
}
S 'END'
