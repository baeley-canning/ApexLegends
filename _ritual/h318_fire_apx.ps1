# h318_fire_on_sight.ps1 - wait for ANY r5apex_dx12, hold 900 ms, inject once, log, exit.
# Long fuse (15 min) so the launch can happen whenever; replaces the short watcher that kept expiring.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h318_fire_apx.out'
$d    = 'C:\Users\Public\p37'
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
Lg '===== fire on sight (15 min fuse) ====='
$sw = [Diagnostics.Stopwatch]::StartNew()
$tp = 0
while ($sw.Elapsed.TotalMinutes -lt 15 -and -not $tp) { Start-Sleep -Milliseconds 250; $g = @(Get-Process r5apex_dx12 -EA 0); if ($g.Count) { $tp = $g[0].Id } }
if (-not $tp) { Lg 'RESULT: NO-OP - no game in 15 min'; Emit; exit 3 }
Lg ('pid=' + $tp + ' - holding 1000 ms')
Start-Sleep -Milliseconds 1000
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $d 'apex_launcher.exe'
$psi.Arguments = ('--inject --method=kernel --pid ' + $tp + ' --driver "' + "$env:SystemRoot\System32\drivers\apexdrv.sys" + '" --dll "C:\Users\Public\apxprobe.dll" --manual-map')
$psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.WorkingDirectory = $d
$txt = ''
try {
    $pr = [System.Diagnostics.Process]::Start($psi)
    $t1 = $pr.StandardOutput.ReadToEndAsync(); $t2 = $pr.StandardError.ReadToEndAsync()
    if (-not $pr.WaitForExit(120000)) { Lg 'launcher TIMEOUT'; try { $pr.Kill() } catch { } }
    if ($t1.Wait(4000)) { $txt = $t1.Result }; try { $txt += $t2.Result } catch { }
} catch { Lg ('LAUNCH FAIL ' + $_.Exception.Message) }
foreach ($ln in ($txt -split "`r?`n")) { if ($ln.Trim()) { Lg ('  | ' + $ln.Trim()) } }
Start-Sleep -Seconds 2
Lg ('alive=' + [bool](Get-Process -Id $tp -EA 0))
$log = Join-Path $env:LOCALAPPDATA ('QwenKern\payload_' + $tp + '.log')
Lg ('oracle=' + $(if (Test-Path $log) { 'PRESENT ' + (Get-Item $log).Length + 'B' } else { 'MISSING' }))
if (Test-Path $log) { foreach ($ln in (Get-Content $log -Tail 8)) { Lg ('  o | ' + $ln) } }
Emit



