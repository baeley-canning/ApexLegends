# h288_gcdiag.ps1 - READ-ONLY guest reachability + crash evidence. No state change at all:
# nothing is created, deleted, started or written in the guest. Its only job is to answer "can I
# talk to the guest again after the 15:14 bugcheck, and what did it leave behind".
$vb  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h288_gcdiag.txt'
$so  = "$env:TEMP\h288o.txt"; $se = "$env:TEMP\h288e.txt"
Remove-Item -LiteralPath $out -Force -EA 0
function W([string]$s) { Add-Content -LiteralPath $out -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) }
function Guest([string]$label, [string]$cmdline) {
    $argv = @('guestcontrol','Win11-Test2','--username','vboxuser','--password','vboxuser','run',
              '--exe','C:\Windows\System32\cmd.exe','--wait-stdout','--wait-stderr','--timeout','30000',
              '--','cmd.exe','/c',$cmdline)
    $p = Start-Process -FilePath $vb -ArgumentList $argv -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    if ($p.WaitForExit(60000)) {
        $t = (((Get-Content $so -Raw -EA 0) + (Get-Content $se -Raw -EA 0)) -replace '\s+', ' ').Trim()
        W ($label + ' rc=' + $p.ExitCode + ' out=[' + $t + ']')
    } else { try { $p.Kill() } catch { }; W ($label + ' TIMEOUT 60 s (killed)') }
}
$info = (& $vb showvminfo 'Win11-Test2' --machinereadable 2>&1) -join "`n"
foreach ($k in 'VMState','GuestAdditionsRunLevel','GuestAdditionsVersion') {
    $m = [regex]::Match($info, "(?m)^$k=`"?(.*?)`"?$")
    W ($k + '=' + ($(if ($m.Success) { $m.Groups[1].Value } else { '?' })))
}
Guest 'alive' 'echo %DATE% %TIME%'
Guest 'boot'  'powershell -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString(\"yyyy-MM-dd HH:mm:ss\")"'
Guest 'dumps' 'dir /b /o-d C:\Windows\Minidump'
Guest 'dumpmeta' 'powershell -NoProfile -Command "Get-ChildItem C:\Windows\Minidump -Filter *.dmp -EA 0 | Select-Object -First 4 | ForEach-Object { $_.Name + \" \" + $_.Length + \" \" + $_.LastWriteTime.ToString(\"HH:mm:ss\") }"'
Guest 'memdump' 'powershell -NoProfile -Command "if (Test-Path C:\Windows\MEMORY.DMP) { (Get-Item C:\Windows\MEMORY.DMP).Length } else { \"none\" }"'
Guest 'svc' 'sc query zapexdrv'
Guest 'np'  'tasklist /fi "imagename eq notepad.exe" /fo csv /nh'
W 'RESULT: h288 read-only diag complete (nothing mutated)'
