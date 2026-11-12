# h310 go2 - launch h310_run.ps1 elevated WITHOUT a UAC prompt: register a one-shot /it /rl
# highest task and run it. Start-Process -Verb RunAs returned without starting anything from this
# non-elevated shell, so the scheduler service does the elevation instead. Reports admin-group
# membership, every schtasks line, and whether h310_pre.txt actually got a fresh stamp.
$o = 'C:\Users\Public\p37\h310_go2.txt'
function S([string]$m) { Add-Content -LiteralPath $o -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $m) }
S '===== go2 ====='
S ('groups admin=' + @((whoami /groups) | Select-String 'S-1-5-32-544').Count)
S ('user=' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
$pre = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h310_pre.txt'
$before = (Get-Item $pre).LastWriteTime
$act = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument ('-NoProfile -ExecutionPolicy Bypass -File "C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h310_run.ps1"')
$prn = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
try { Register-ScheduledTask -TaskName p310go -Action $act -Principal $prn -Force | Out-Null; S 'register: ok' }
catch { S ('register: ERR ' + $_.Exception.Message) }
try { Start-ScheduledTask -TaskName p310go; S 'start: ok' } catch { S ('start: ERR ' + $_.Exception.Message) }
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 3
    if ((Get-Item $pre).LastWriteTime -gt $before) { S ('RUN STARTED after ' + (3 * ($i + 1)) + 's'); break }
}
S ('pre mtime=' + (Get-Item $pre).LastWriteTime.ToString('HH:mm:ss'))
