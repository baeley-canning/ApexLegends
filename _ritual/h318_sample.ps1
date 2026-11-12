# h318_sample.ps1 - when does arbitrary allocation in the game start being denied?
# Kills any current game, starts a fresh one, and runs the alloc probe at fixed offsets from process
# creation. No driver, no payload - this only measures the window the mapper needs.
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here 'h318_sample.out'
$probe = Join-Path $here 'h318_allocprobe.ps1'
$exe = 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe'
$L = New-Object System.Collections.Generic.List[string]
function Lg([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; $L.Add($line); Write-Host $line }
function Emit { Set-Content -LiteralPath $out -Value ($L -join "`r`n") }
Get-Process r5apex_dx12 -EA 0 | Stop-Process -Force -EA 0
Start-Sleep -Seconds 4
$known = @(Get-Process r5apex_dx12 -EA 0 | ForEach-Object { $_.Id })
Lg ('waiting for a new game process (up to 240 s), preexisting=[' + ($known -join ',') + ']')
$sw = [Diagnostics.Stopwatch]::StartNew()
$tp = 0
while ($sw.Elapsed.TotalSeconds -lt 240 -and -not $tp) {
    Start-Sleep -Milliseconds 100
    foreach ($p in @(Get-Process r5apex_dx12 -EA 0)) { if ($known -notcontains $p.Id) { $tp = $p.Id; break } }
}
if (-not $tp) { Lg 'RESULT: FAIL - no new process'; Emit; exit 1 }
Lg ('new pid=' + $tp + ' at +' + [math]::Round($sw.Elapsed.TotalSeconds, 2) + 's')
foreach ($off in 2, 5, 10, 20, 35) {
    while ($sw.Elapsed.TotalSeconds -lt $off) { Start-Sleep -Milliseconds 100 }
    if (-not (Get-Process -Id $tp -EA 0)) { Lg ('t+' + $off + 's: process gone'); break }
    $r = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $probe -TargetPid $tp -Label ('t+' + $off + 's')
    Lg ($r -join ' ')
}
Get-Process -Id $tp -EA 0 | Select-Object -Expand Id | ForEach-Object { Lg ('alive at end=' + $_) }
Emit
