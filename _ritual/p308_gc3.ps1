# p308_gc3.ps1 - probe #308 (variable: helper renamed, GC was the Get-Content alias)
$d   = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v   = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$out = Join-Path $d 'p308.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function Call([string]$c2, [string]$tag, [int]$to = 90000) {
    $o = & $v guestcontrol $VM run --exe 'C:\Windows\System32\cmd.exe' --username vboxuser --password vboxuser --timeout $to --wait-stdout --wait-stderr -- 'cmd' ('/c ' + $c2) 2>&1
    Say ('{0} rc={1} o={2}' -f $tag, $LASTEXITCODE, ($o -join ' '))
    return $LASTEXITCODE
}
Say 'START'
Say ('ga=' + ((& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=') -replace '.*=', ''))
$rc = Call 'echo WARM' 'warm'
Say ('warm_ok=' + ($rc -eq 0))
if ($rc -ne 0) { Say 'VERDICT: no session - fall back to typed shell'; Say 'END'; return }
Call 'sc query WinRing0x64 > C:\Users\Public\p308_svc.txt 2>&1 & sc query zapexdrv >> C:\Users\Public\p308_svc.txt 2>&1 & sc query EchoDrv >> C:\Users\Public\p308_svc.txt 2>&1 & sc query pcdsrvc_x64 >> C:\Users\Public\p308_svc.txt 2>&1 & sc query GLCKio2 >> C:\Users\Public\p308_svc.txt 2>&1' 'svc'
Call 'tasklist /v > C:\Users\Public\p308_ps.txt 2>&1' 'ps'
Call 'driverquery /v > C:\Users\Public\p308_drv.txt 2>&1 & bcdedit /enum {current} > C:\Users\Public\p308_bcd.txt 2>&1' 'drv+bcd'
Call 'powershell -c "Get-WinEvent -FilterHashtable @{LogName=''System'';Id=1001,41,6008,219} -MaxEvents 40 -EA 0 | Select-Object TimeCreated,Id,ProviderName,Message | Out-File C:\Users\Public\p308_ev.txt -Width 400; Get-ChildItem C:\Windows\Minidump\*.dmp -EA 0 | Out-File -Append C:\Users\Public\p308_ev.txt -Width 400"' 'ev'
foreach ($f in 'svc', 'ps', 'drv', 'bcd', 'ev') {
    & $v guestcontrol $VM copyfrom --username vboxuser --password vboxuser ('C:\Users\Public\p308_' + $f + '.txt') (Join-Path $d ('p308_' + $f + '.txt')) 2>&1 | Out-Null
    $t = Join-Path $d ('p308_' + $f + '.txt')
    Say ('{0} copied={1}' -f $f, (Test-Path $t))
}
Say 'END'