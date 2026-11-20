# cpu_probe.ps1 - 6 s CPU-time delta on producer PID 11932 (grind-vs-stall discriminator)
$out = Join-Path $PSScriptRoot 'cpu_probe.txt'
$p = Get-Process -Id 11932 -ErrorAction SilentlyContinue
if (-not $p) {
    Set-Content -LiteralPath $out 'PROD_DEAD'
    exit
}
$c1 = $p.TotalProcessorTime.TotalSeconds
Start-Sleep -Seconds 6
$p.Refresh()
$c2 = $p.TotalProcessorTime.TotalSeconds
Set-Content -LiteralPath $out ('PROD_ALIVE cpudelta={0:N2}s over 6s wall threads={1} ws={2:N0}MB' -f ($c2 - $c1), $p.Threads.Count, ($p.WorkingSet64 / 1MB))