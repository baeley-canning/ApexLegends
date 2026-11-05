# p44f: elevated runner cloned from p43q, same pure-read class.  p43o's runner
# fixes stay (--why, own output files, OUT archived before the run); new is the
# 4 KiB rescue inside name_hits and the 26200 layout.  The runner only checks
# prerequisites and archives -- it never touches the device itself.
# Usage: powershell -File C:\Windows\Temp\p44f_run.ps1 --pid=<n> [--hex] [--why]
$ErrorActionPreference = 'Continue'
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$log  = Join-Path $repo 'temp\p44f_run.txt'
$prg  = Join-Path $repo '_ritual\p44f_progress.txt'
$out  = Join-Path $repo '_ritual\p44f_livedump.txt'
$prev = Join-Path $repo '_ritual\p44f_livedump.prev.txt'
$con  = Join-Path $repo 'temp\p44f_console.txt'
$err  = Join-Path $repo 'temp\p44f_err.txt'
function W($t) { ('{0}  {1}' -f (Get-Date -f 'HH:mm:ss.fff'), $t) | Out-File -Append -Encoding utf8 $log }

$Pid2 = ''; $lo = ''; $hi = ''; $chunk = ''; $hex = ''; $why = ''
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = [string]$args[$i]
    if     ($a -like '--pid=*')   { $Pid2  = $a.Substring(6) }
    elseif ($a -like '--lo=*')    { $lo    = $a.Substring(5) }
    elseif ($a -like '--hi=*')    { $hi    = $a.Substring(5) }
    elseif ($a -like '--chunk=*') { $chunk = $a.Substring(8) }
    elseif ($a -eq '--hex')   { $hex   = '1' }
    elseif ($a -eq '--why')   { $why   = '1' }
}
if (-not $Pid2) { W 'RESULT: no --pid'; exit 4 }
"=== p44f $(Get-Date -f o) ===" | Set-Content -Encoding utf8 $log
W "ELEVATED start pid_arg=$Pid2 lo=$lo hi=$hi hex=$hex why=$why"
('=== run pid=' + $Pid2 + ' hex=' + $hex + ' why=' + $why) | Out-File -Append -Encoding utf8 $prg

$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
W "elevated=$elev"
if (-not $elev) { W 'RESULT: not elevated -- abort, re-stage this script via RunAs'; exit 3 }

$alive = [bool](Get-Process -Id $Pid2 -EA 0)
W "game alive=$alive"
if (-not $alive) { W 'RESULT: game gone, abort'; exit 2 }

if (Test-Path -LiteralPath $out) { Copy-Item -LiteralPath $out -Destination $prev -Force; W "archived previous OUT to $prev" }
Remove-Item -LiteralPath $out, $con, $err -EA 0

$py  = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$src = Join-Path $repo 'ext\basehunt.py'
$pa  = '-u "' + $src + '" --inplace --pid=' + $Pid2
if ($lo)    { $pa += ' --lo=' + $lo }
if ($hi)    { $pa += ' --hi=' + $hi }
if ($chunk) { $pa += ' --chunk=' + $chunk }
if ($hex)   { $pa += ' --hex' }
if ($why)   { $pa += ' --why' }

W ('running: ' + $py + ' ' + $pa)
$env:DUMP_OUT  = 'p44f_livedump.txt'
$env:DUMP_PROG = 'p44f_progress.txt'
$t0 = Get-Date
$p = Start-Process -FilePath $py -ArgumentList $pa -WorkingDirectory (Join-Path $repo 'ext') `
      -PassThru -RedirectStandardOutput $con -RedirectStandardError $err
W ('child pid=' + $p.Id + ' started ' + (Get-Date -f 'HH:mm:ss.fff'))
$finished = $p.WaitForExit(1200000)
if (-not $finished) { $p.Kill(); W 'RESULT: killed after 1200 s' }
$rc = if ($p.HasExited) { $p.ExitCode } else { -1 }
W ("child exit=$rc wall={0:N1}s" -f ((Get-Date).Subtract($t0)).TotalSeconds)
W ('OUT exists=' + (Test-Path -LiteralPath $out) + ' size=' + (Get-Item -LiteralPath $out -EA 0).Length)
W ('console tail: ' + ((Get-Content -LiteralPath $con -EA 0 -Tail 12) -join ' | '))
W ('err tail: ' + ((Get-Content -LiteralPath $err -EA 0 -Tail 6) -join ' | '))
$v = (Select-String -LiteralPath $out -Pattern '^VERDICT: (.+)$' -EA 0 | Select-Object -Last 1).Matches[0].Groups[1].Value
W ('RESULT: verdict=' + $v)
W ('post game alive=' + [bool](Get-Process -Id $Pid2 -EA 0))
W '--- end ---'
if ($v -like 'DUMP_OK*') { exit 0 } else { exit 1 }









