# p57_window.ps1 -- resumable windowed needle sweep. One child process per
# window; a window that stalls past its budget is killed and the walk moves on,
# so a bad physical range cannot take the whole strip (or the box) with it.
# Read-only. Run self-elevated:  Start-Process powershell -Verb RunAs -ArgumentList ...
param(
    [string]$Lo   = '0x0eda00000',
    [string]$Hi   = '0x7eda00000',
    [string]$Step = '0x0e000000',
    [string]$Needle = '76561198060599900',
    [int]$MaxS = 45,
    [string]$OutDir = 'temp'
)
$root = Split-Path -Parent $PSScriptRoot
$adm = [bool](([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator))
if (-not $adm) {
    $args = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Key -eq 'OutDir') { $args += ' -OutDir "' + $kv.Value + '"' }
        else { $args += ' -' + $kv.Key + ' ' + $kv.Value }
    }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -Wait
    $l = Get-ChildItem (Join-Path $root $OutDir) -Filter 'p57_wind_*.log' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($l) { Get-Content -LiteralPath $l.FullName -Tail 25 }
    exit 0
}
Set-Location $root
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$nlo = [uint64]$Lo; $nhi = [uint64]$Hi; $nstep = [uint64]$Step
$log = Join-Path $OutDir ('p57_wind_{0}.log' -f (Get-Date -Format 'HHmmss'))
$hits = New-Object System.Collections.ArrayList
function Say($s) { $s | Tee-Object -FilePath $log -Append }

Say ("# p57_window {0} needle={1} 0x{2}-0x{3} step=0x{4} max_s={5}" -f `
        (Get-Date -Format 'HH:mm:ss'), $Needle, $nlo.ToString('x'), $nhi.ToString('x'),
    $nstep.ToString('x'), $MaxS)
$win = 0
$top = $nhi
while ($top -gt $nlo) {
    $bottom = [uint64][Math]::Max([double]($top - $nstep), [double]$nlo)
    $out = Join-Path $OutDir ('p57_w{0:d2}.txt' -f $win)
    $bh = $bottom.ToString('x'); $th = $top.ToString('x')
    Say ("WIN {0} 0x{1}-0x{2} -> {3}" -f $win, $bh, $th, $out)
    $p = Start-Process python -PassThru -WindowStyle Hidden -ArgumentList `
        "ext\p56_hits.py", "--needle=$Needle", ('--lo=0x' + $bh), `
        ('--hi=0x' + $th), "--sig", "--max_s=$MaxS", "--out=$out"
    $done = $p.WaitForExit(($MaxS + 15) * 1000)
    if (-not $done) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        Say ("WIN {0} KILLED after {1}s" -f $win, $MaxS + 15)
    }
    if (Test-Path $out) {
        $n = @(Select-String -Path $out -Pattern '^HIT (sig )?addr=' -CaseSensitive).Count
        $sum = (Select-String -Path $out -Pattern '^hits=').Line
        Say ("WIN {0} exit={1} hitlines={2} {3}" -f $win, $(if ($done) { $p.ExitCode } else { 'kill' }), $n, $sum)
        if ($n -gt 0) { Copy-Item $out (Join-Path $OutDir 'p57_found.txt') -Force; [void]$hits.Add($out) }
    } else { Say ("WIN {0} NO_OUTPUT" -f $win) }
    if ($hits.Count -gt 0) { break }
    $top = $bottom
    $win++
}
Say ("DONE wins={0} found={1}" -f $win, $hits.Count)
