# p300_gc.ps1 - probe #300 (variable: guestcontrol session warm-up + retry before the pull)
# #282 died at the very first call: "Error starting guest session (current status is: starting)" at
# 30 s. VBoxService is alive (ga=3) but a fresh GA install needs a longer handshake and the first
# session start is slow. Warm up with 3 x 120 s attempts; only if one returns 0 do the pulls.
$d    = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM   = 'Win11-Test2'
$U    = 'vboxuser'
$P    = 'password'
$gd   = 'C:\Users\Public\p300'
$out  = Join-Path $d 'p300.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function G([string[]]$a) { $o = (& $v guestcontrol $VM --username $U --password $P @a 2>&1) -join ' / '; return @{ rc = $LASTEXITCODE; o = $o } }
function PSG([string]$c) { G @('run', '--exe', 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe', '--wait-stdout', '--wait-stderr', '--timeout', '120000', '--', 'powershell.exe', '-NoProfile', '-Command', $c) }

Say 'START'
Say ('ga=' + ((& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=') -replace '.*='))
$ok = $false
for ($i = 1; $i -le 3; $i++) {
    $w = G @('run', '--exe', 'C:\Windows\System32\cmd.exe', '--wait-stdout', '--timeout', '120000', '--', 'cmd.exe', '/c', 'echo WARM')
    Say ('warm{0} rc={1} o={2}' -f $i, $w.rc, $w.o)
    if ($w.rc -eq 0) { $ok = $true; break }
    Start-Sleep -Seconds 5
}
Say ('warm_ok=' + $ok)
if ($ok) {
    $mk = G @('run', '--exe', 'C:\Windows\System32\cmd.exe', '--wait-stdout', '--timeout', '60000', '--', 'cmd.exe', '/c', ('if not exist ' + $gd + ' md ' + $gd + ' & echo OK'))
    Say ('mkdir rc={0} {1}' -f $mk.rc, $mk.o)
    $svc = PSG "Get-CimInstance Win32_Service | ? { `$_.Name -match 'VBoxService|VBoxMouse|VBoxSF' } | % { `$_.Name, `$_.State, `$_.StartMode } | Out-File $gd\svc.txt -Encoding utf8; Get-CimInstance Win32_Process | ? { `$_.Name -match 'echo|pca|apex|easy|winring|zap|VBox' } | % { `$_.Name, `$_.ProcessId } | Out-File $gd\proc.txt -Encoding utf8"
    Say ('svc rc={0} {1}' -f $svc.rc, $svc.o)
    $ev = PSG "Get-WinEvent -FilterHashtable @{LogName='System';Id=1001,41,6008,219} -Max 20 | fl TimeCreated,Id,Message | Out-File $gd\ev.txt -Encoding utf8"
    Say ('ev rc={0} {1}' -f $ev.rc, $ev.o)
    $drv = PSG "Get-CimInstance Win32_SystemDriver | ? { `$_.Name -match 'apex|echo|pca|winring|zap|vbox|gdrv|kdu' } | % { `$_.Name, `$_.State, `$_.StartMode, `$_.PathName } | Out-File $gd\drv.txt -Encoding utf8"
    Say ('drv rc={0} {1}' -f $drv.rc, $drv.o)
    $dmp = PSG "gci C:\Windows\Minidump\*.dmp | % { `$_.Name; (Select-String -Path `$_.FullName -Pattern '([\w-]+\.sys)' -AllMatches -Encoding unicode).Matches.Value | sort -Unique } | Out-File $gd\dumps.txt -Encoding utf8"
    Say ('dumps rc={0} {1}' -f $dmp.rc, $dmp.o)
    $bcd = PSG "bcdedit /enum '{current}' | Out-File $gd\bcd.txt -Encoding utf8"
    Say ('bcd rc={0} {1}' -f $bcd.rc, $bcd.o)
    Start-Sleep -Seconds 3
    foreach ($n in 'svc', 'proc', 'ev', 'drv', 'dumps', 'bcd') {
        $loc = Join-Path $d ('p300_{0}.txt' -f $n)
        Remove-Item -LiteralPath $loc -Force -ErrorAction SilentlyContinue
        $cf = G @('copyfrom', ($gd + '\' + $n + '.txt'), $loc)
        Say ('copy {0} rc={1} local={2}' -f $n, $cf.rc, (Test-Path -LiteralPath $loc))
        if (Test-Path -LiteralPath $loc) { (Get-Content -LiteralPath $loc -TotalCount 30) | ForEach-Object { Say ('  | ' + $_) } }
    }
} else {
    Say 'VERDICT: guestcontrol still cannot open a session - fall back to the screenshot route'
}
Say 'END'