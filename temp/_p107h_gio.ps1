# _p107h_gio.ps1 - SAME probe as p107g (no new python: calls _p107g_gio.py unchanged),
# but crash-durable. p107g's OUT is truncated by open("w") at process start, so a crash
# right after launch leaves a zero-byte out file indistinguishable from "never ran".
# This wrapper writes a stamped marker BEFORE the py starts, samples the out size at +5 s,
# and copies the out to a run-stamped keep-file on exit (crash or not).
# Read-only, R4 vacuous. Writes: _p107h_marker.txt, _p107g_out_<stamp>.txt
param([switch]$Inner)
$py = 'C:\Users\New User\AppData\Local\Programs\Python\Python312\python.exe'
$f  = Join-Path $PSScriptRoot '_p107g_gio.py'
$mk = Join-Path $PSScriptRoot '_p107h_marker.txt'
$out = Join-Path $PSScriptRoot '_p107g_out.txt'
function M([string]$s) { ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) | Add-Content -LiteralPath $mk -Encoding UTF8 }
if (-not $Inner) {
    $adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
    if ($adm) {
        Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Inner') -WindowStyle Hidden
        exit 0
    }
    $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs -Wait
    exit 0
}
$stamp = Get-Date -f 'yyyyMMdd_HHmmss'
M ('RUN ' + $stamp + ' up=' + [int]((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalMinutes + 'min')
M ('out_before=' + (Test-Path -LiteralPath $out) + ' size=' + [int64]((Get-Item $out -EA 0).Length))
$p = Start-Process -FilePath $py -ArgumentList ('"' + $f + '"') -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $PSScriptRoot '_p107h_stdout.txt') -RedirectStandardError (Join-Path $PSScriptRoot '_p107h_stderr.txt')
M ('launched pid=' + $p.Id)
Start-Sleep -Seconds 5
$sz = [int64]((Get-Item $out -EA 0).Length)
M ('out_at_5s size=' + $sz)
if ($sz -le 0) { M 'WARN: out still empty at 5 s - py may not have started' }
$p.WaitForExit(180000) | Out-Null
M ('exit=' + $(try { $p.ExitCode } catch { '?' }))
$keep = Join-Path $PSScriptRoot ('_p107g_out_' + $stamp + '.txt')
if (Test-Path -LiteralPath $out) { Copy-Item -LiteralPath $out -Destination $keep -Force; M ('kept ' + (Split-Path $keep -Leaf) + ' size=' + (Get-Item $keep).Length) }
M 'END'
