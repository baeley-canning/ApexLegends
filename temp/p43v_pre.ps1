# p43v pre-state (R3).  Pure-read probe: device open only, no load/DSE/service
# touch, so the only pre-state that matters is the transport, the game and the
# exact source that will run.  READ-ONLY host scan, same safe class as p40-p43q.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p43v_pre.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$g = Get-Process -Id 5488 -EA 0
if ($g) { $L.Add("GAME alive pid=5488 ws=$([int]($g.WorkingSet64/1MB))MB") } else { $L.Add('GAME gone pid=5488') }
$src = Join-Path $repo 'ext\dumplive.py'
foreach ($pat in '^NAME = ', '^OFF_NAME = ', '^PC_OFF = ', '^NAME_DELTAS = ',
                 '^PID_OFFS = ', '^LINK_OFF = ', '^MIN_SCORE = ', '^HIT_CAP = ',
                 '^HEX_WIN = ') {
    $m = (Select-String -LiteralPath $src -Pattern $pat).Matches
    $ln = (Select-String -LiteralPath $src -Pattern $pat | Select-Object -First 1).Line
    $L.Add('const ' + $(if ($ln) { $ln.Trim() } else { 'MISSING ' + $pat }))
}
$L.Add('rescue-loop=' + [bool](Select-String -LiteralPath $src -Pattern 'bad4k=%d rescued=%d'))
$L.Add('ret4=' + [bool](Select-String -LiteralPath $src -Pattern 'return hits, skipped, chunks, rescued'))
$L.Add('dumplive sha256=' + (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash)
$L.Add('drv(gio)=' + ((Get-CimInstance Win32_SystemDriver -EA 0 |
    Where-Object { $_.Name -match 'gio|gdrv' } |
    ForEach-Object { "$($_.Name):$($_.State):$($_.Started)" }) -join ','))
$L.Add('prev p43v dump=' + (Test-Path -LiteralPath (Join-Path $repo '_ritual\p43v_livedump.txt')))
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
if (-not $g) { Add-Content -LiteralPath $o -Value 'ABORT game gone'; exit 2 }
$prg = Join-Path $repo '_ritual\p43v_progress.txt'
if (Test-Path -LiteralPath $prg) { Remove-Item -LiteralPath $prg -Force }
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p43v_run.ps1', '--pid=5488', '--hex', '--why'
Add-Content -LiteralPath $o -Value ('LAUNCHED pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o

