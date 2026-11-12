# h310 go - launch the elevated h310_run.ps1 from a NON-elevated shell (UAC prompt), then report
# whether the run actually started (fresh stamp on h310_pre.txt). Separate script so a retry is
# one command and every attempt is logged.
$o = 'C:\Users\Public\p37\h310_go.txt'
function S([string]$m) { Add-Content -LiteralPath $o -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $m) }
S ('===== go, admin=' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) + ' =====')
$pre = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h310_pre.txt'
$before = if (Test-Path $pre) { (Get-Item $pre).LastWriteTime } else { [datetime]::MinValue }
S ('pre mtime before=' + $before.ToString('HH:mm:ss'))
try {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\h310_run.ps1')
    S 'Start-Process returned'
} catch { S ('LAUNCH ERR ' + $_.Exception.Message) }
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Seconds 3
    if ((Test-Path $pre) -and (Get-Item $pre).LastWriteTime -gt $before) { S ('RUN STARTED after ' + (3 * ($i + 1)) + 's'); break }
}
S ('pre mtime after=' + (Get-Item $pre).LastWriteTime.ToString('HH:mm:ss'))
