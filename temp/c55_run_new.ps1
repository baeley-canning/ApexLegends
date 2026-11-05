# p44f: elevated runner cloned from p43q, same pure-read class.  p43o's runner
# fixes stay (--why, own output files, OUT archived before the run).  p44f adds
# the basehunt contract: --dry / --from / --max-s pass through, and a PARTIAL
# verdict (budget spent) is re-driven with --from=<resume_pa> instead of being
# reported as a failure.  The runner only checks prerequisites and archives --
# it never touches the device itself.
# Usage: powershell -File C:\Windows\Temp\p44f_run.ps1 --pid=<n> [--dry[=N]]
#        [--max-s=N] [--from=0xPA] [--link=0xPA --fl=0xKVA --bl=0xKVA]
# The decoy trio (--link/--fl/--bl) is per-launch; it travels via DUMP_* env to
# basehunt so the accept run needs no code edit after a discovery pass.
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
$dry = ''; $maxs = ''; $from = ''; $tries = ''; $lnk = ''; $fl = ''; $bl = ''
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = [string]$args[$i]
    if     ($a -like '--pid=*')    { $Pid2  = $a.Substring(6) }
    elseif ($a -like '--lo=*')     { $lo    = $a.Substring(5) }
    elseif ($a -like '--hi=*')     { $hi    = $a.Substring(5) }
    elseif ($a -like '--chunk=*')  { $chunk = $a.Substring(8) }
    elseif ($a -like '--max-s=*')  { $maxs  = $a.Substring(8) }
    elseif ($a -like '--from=*')   { $from  = $a.Substring(7) }
    elseif ($a -like '--dry=*')    { $dry   = $a.Substring(6) }
    elseif ($a -like '--tries=*')  { $tries = $a.Substring(8) }
    elseif ($a -like '--link=*')   { $lnk   = $a.Substring(7) }
    elseif ($a -like '--fl=*')     { $fl    = $a.Substring(5) }
    elseif ($a -like '--bl=*')     { $bl    = $a.Substring(5) }
    elseif ($a -eq '--dry')   { $dry   = '1' }
    elseif ($a -eq '--hex')   { $hex   = '1' }
    elseif ($a -eq '--why')   { $why   = '1' }
}
if (-not $Pid2) { W 'RESULT: no --pid'; exit 4 }
if (-not $tries) { $tries = '40' }
"=== p44f $(Get-Date -f o) ===" | Set-Content -Encoding utf8 $log
W "ELEVATED start pid_arg=$Pid2 lo=$lo hi=$hi hex=$hex why=$why dry=$dry max_s=$maxs from=$from link=$lnk fl=$fl bl=$bl"
('=== run pid=' + $Pid2 + ' dry=' + $dry + ' from=' + $from) | Out-File -Append -Encoding utf8 $prg

$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
W "elevated=$elev"
if (-not $elev) { W 'RESULT: not elevated -- abort, re-stage this script via RunAs'; exit 3 }

$alive = [bool](Get-Process -Id $Pid2 -EA 0)
W "game alive=$alive dry=$dry"
if (-not $alive -and -not $dry) { W 'RESULT: game gone, abort'; exit 2 }
if (-not $alive) { W 'game gone but --dry: hunt only, no dump' }

if (Test-Path -LiteralPath $out) { Copy-Item -LiteralPath $out -Destination $prev -Force; W "archived previous OUT to $prev" }
Remove-Item -LiteralPath $out, $con, $err -EA 0

$py  = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$src = Join-Path $repo 'ext\basehunt.py'
$env:DUMP_OUT  = 'p44f_livedump.txt'
$env:DUMP_PROG = 'p44f_progress.txt'
$env:DUMP_PID  = $Pid2
if ($lnk) { $env:DUMP_LINK = $lnk }
if ($fl)  { $env:DUMP_FL   = $fl }
if ($bl)  { $env:DUMP_BL   = $bl }
W ("env DUMP_PID=$($env:DUMP_PID) DUMP_LINK=$($env:DUMP_LINK) DUMP_FL=$($env:DUMP_FL) DUMP_BL=$($env:DUMP_BL)")
$t0 = Get-Date
$v = ''
$attempt = 0
$rc = -1
while ($attempt -lt [int]$tries) {
    $attempt++
    $pa = '-u "' + $src + '" --inplace --pid=' + $Pid2
    if ($lo)    { $pa += ' --lo=' + $lo }
    if ($hi)    { $pa += ' --hi=' + $hi }
    if ($chunk) { $pa += ' --chunk=' + $chunk }
    if ($hex)   { $pa += ' --hex' }
    if ($why)   { $pa += ' --why' }
    if ($dry)   { $pa += ' --dry=' + $dry }
    $bud = if ($maxs) { $maxs } else { '40' }
    $pa += ' --max-s=' + $bud
    if ($from)  { $pa += ' --from=' + $from }
    W ("attempt $attempt running: " + $pa)
    $p = Start-Process -FilePath $py -ArgumentList $pa -WorkingDirectory (Join-Path $repo 'ext') `
          -PassThru -RedirectStandardOutput $con -RedirectStandardError $err
    W ('child pid=' + $p.Id + ' started ' + (Get-Date -f 'HH:mm:ss.fff'))
    $finished = $p.WaitForExit(300000)
    if (-not $finished) { $p.Kill(); W 'RESULT: killed after 300 s' }
    $p.Refresh()
    $rc = $p.ExitCode
    if ($null -eq $rc) { $rc = -1 }
    W (("child exit=$rc wall={0:N1}s total={1:N1}s" -f ((Get-Date).Subtract($t0).TotalSeconds,
        (Get-Date).Subtract($t0).TotalSeconds)))
    $v = (Select-String -LiteralPath $out -Pattern '^VERDICT: (.+)$' -EA 0 | Select-Object -Last 1).Matches[0].Groups[1].Value
    # -RedirectStandardOutput leaves Process.ExitCode empty; the verdict is the
    # verdict (R3), so derive rc from it instead of logging a -1.
    $rc = if ($v -like 'DUMP_OK*' -or $v -like 'DRY_*') { 0 } else { 1 }
    W ('attempt ' + $attempt + ' verdict=' + $v)
    if ($v -like 'PARTIAL*') {
        $m = [regex]::Match($v, 'resume_pa=(0x[0-9a-fA-F]+)')
        if (-not $m.Success) { W 'RESULT: PARTIAL without resume_pa -- stop'; break }
        $from = $m.Groups[1].Value
        W ('budget spent, resume at ' + $from)
        Start-Sleep -Seconds 2
        continue
    }
    break
}
W ('OUT exists=' + (Test-Path -LiteralPath $out) + ' size=' + (Get-Item -LiteralPath $out -EA 0).Length)
W ('console tail: ' + ((Get-Content -LiteralPath $con -EA 0 -Tail 12) -join ' | '))
W ('err tail: ' + ((Get-Content -LiteralPath $err -EA 0 -Tail 6) -join ' | '))
W ('RESULT: verdict=' + $v + ' attempts=' + $attempt)
W ('post game alive=' + [bool](Get-Process -Id $Pid2 -EA 0))
W '--- end ---'
if ($v -like 'DUMP_OK*' -or $v -like 'DRY_*') { exit 0 } else { exit 1 }
