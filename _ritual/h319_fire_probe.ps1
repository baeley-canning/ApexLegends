# h319_fire_probe.ps1 - h319: TRANSIENT kernel probe (alloc 4K RW -> write 1 byte -> free),
# fired 1 s after the game appears, then 60 s liveness watch.  One variable: residency
# (probe leaves NOTHING in the target) vs the h318 control (inert payload left resident).
# Verdict: DEAD -> transient foreign ops kill too; ALIVE 60 s -> residency is the killer.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h319_fire_probe.out'
$d    = 'C:\Users\Public\p37'
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
Lg '===== h319 transient probe (15 min fuse) ====='
$sw = [Diagnostics.Stopwatch]::StartNew()
$tp = 0
while ($sw.Elapsed.TotalMinutes -lt 15 -and -not $tp) { Start-Sleep -Milliseconds 250; $g = @(Get-Process r5apex_dx12 -EA 0); if ($g.Count) { $tp = $g[0].Id } }
if (-not $tp) { Lg 'RESULT: NO-OP - no game in 15 min'; Emit; exit 3 }
Lg ('pid=' + $tp + ' - holding 1000 ms')
Start-Sleep -Milliseconds 1000
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $d 'apex_launcher.exe'
$psi.Arguments = ('--probe --pid=' + $tp + ' --driver "' + "$env:SystemRoot\System32\drivers\apexdrv.sys" + '"')
$psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.WorkingDirectory = $d
$txt = ''
$psw = [Diagnostics.Stopwatch]::StartNew()
try {
    $pr = [System.Diagnostics.Process]::Start($psi)
    $t1 = $pr.StandardOutput.ReadToEndAsync(); $t2 = $pr.StandardError.ReadToEndAsync()
    if (-not $pr.WaitForExit(120000)) { Lg 'launcher TIMEOUT'; try { $pr.Kill() } catch { } }
    if ($t1.Wait(4000)) { $txt = $t1.Result }; try { $txt += $t2.Result } catch { }
} catch { Lg ('LAUNCH FAIL ' + $_.Exception.Message) }
foreach ($ln in ($txt -split "`r?`n")) { if ($ln.Trim()) { Lg ('  | ' + $ln.Trim()) } }
Lg ('probe returned at +' + [int]$psw.Elapsed.TotalMilliseconds + ' ms')
# 60 s liveness watch, 1 s polling; report the exact second the game died.
$died = -1
for ($i = 1; $i -le 60; $i++) {
    Start-Sleep -Milliseconds 1000
    if (-not (Get-Process -Id $tp -EA 0)) { $died = $i; break }
}
if ($died -gt 0) { Lg ('VERDICT: DEAD +' + $died + ' s after probe returned -> transient foreign ops kill') }
else { Lg 'VERDICT: ALIVE 60 s after probe -> transient ops safe, residency is the killer' }
Emit
