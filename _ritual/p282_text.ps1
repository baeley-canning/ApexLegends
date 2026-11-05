# p282_text.ps1 - probe #282 (variable: read-through via guestcontrol instead of screenshots)
# Runs only after p281 shows a live normal desktop (VBoxService 1084 in safe mode => guestcontrol is
# dead there). Pulls the crash identity as TEXT: bugcheck codes, dump module lists, 3rd-party driver
# table (apex/echo/pca/winring/zap/vbox/gdrv), bcd, verifier. Conventions from p272j: credentials
# vboxuser/password, mkdir before copy, one summary file.
$d    = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$v    = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM   = 'Win11-Test2'
$U    = 'vboxuser'
$P    = 'password'
$gd   = 'C:\Users\Public\p282'
$out  = Join-Path $d 'p282.txt'
function Say($t) { ("{0} {1}" -f (Get-Date -f 'HH:mm:ss'), $t) | Out-File -FilePath $out -Encoding ascii -Append }
function G([string[]]$a) { $o = (& $v guestcontrol $VM --username $U --password $P @a 2>&1) -join ' / '; return @{ rc = $LASTEXITCODE; o = $o } }
function PSG([string]$c) { G @('run', '--exe', 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe', '--wait-stdout', '--wait-stderr', '--timeout', '90000', '--', 'powershell.exe', '-NoProfile', '-Command', $c) }

Say 'START'
Say ('ga=' + ((& $v showvminfo $VM --machinereadable | Select-String 'GuestAdditionsRunLevel=') -replace '.*=' ))
$mk = G @('run', '--exe', 'C:\Windows\System32\cmd.exe', '--wait-stdout', '--timeout', '30000', '--', 'cmd.exe', '/c', ('if not exist ' + $gd + ' md ' + $gd + ' & echo OK'))
Say ('mkdir rc={0} {1}' -f $mk.rc, $mk.o)
PSG ("Get-WinEvent -FilterHashtable @{LogName='System';Id=1001,41,6008} -Max 20 | fl TimeCreated,Id,Message | Out-File {0}\ev.txt -Encoding utf8" -f $gd) | Out-Null
PSG ("Get-CimInstance Win32_SystemDriver | ? {{ `$_.Name -match 'apex|echo|pca|winring|zap|vbox|gdrv|kdu' }} | % {{ `$_.Name, `$_.State, `$_.StartMode, `$_.PathName }} | Out-File {0}\drv.txt -Encoding utf8" -f $gd) | Out-Null
PSG ("gci C:\Windows\Minidump\*.dmp | % {{ `$_.Name; (Select-String -Path `$_.FullName -Pattern '([\w-]+\.sys)' -AllMatches -Encoding unicode).Matches.Value | sort -Unique }} | Out-File {0}\dumps.txt -Encoding utf8" -f $gd) | Out-Null
PSG ("bcdedit /enum {{default}} | Out-File {0}\bcd.txt -Encoding utf8" -f $gd) | Out-Null
PSG ("verifier /query 2>&1 | Out-File {0}\ver.txt -Encoding utf8; Get-CimInstance Win32_Process | ? {{ `$_.Name -match 'echo|pca|apex|easy' }} | % {{ `$_.Name, `$_.ProcessId }} | Out-File {0}\proc.txt -Append" -f $gd) | Out-Null
Start-Sleep -Seconds 3

foreach ($n in 'ev', 'drv', 'dumps', 'bcd', 'ver', 'proc') {
    $loc = Join-Path $d ('p282_{0}.txt' -f $n)
    Remove-Item -LiteralPath $loc -Force -ErrorAction SilentlyContinue
    $cf = G @('copyfrom', ($gd + '\' + $n + '.txt'), $loc)
    Say ('copy {0} rc={1} local={2}' -f $n, $cf.rc, (Test-Path -LiteralPath $loc))
    if (Test-Path -LiteralPath $loc) { (Get-Content -LiteralPath $loc -TotalCount 25) | ForEach-Object { Say ('  | ' + $_) } }
}
Say 'VERDICT: pass if ev.txt shows our 2:46 reset and drv.txt names the third-party drivers; dumps.txt names the faulting modules'
Say 'END'
