# p47 pre-state (R3) + elevated stage.  VARIABLE = live-match needle set.
# Needles come from temp\p47_needles.txt (one scoreboard name per line, ASCII).
# A page holding two different needles is an entity-array candidate, so the run
# logs COOC pages and every hit's PA.  Pure read.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p47_pre.txt'
$nl   = Join-Path $repo 'temp\p47_needles.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$g = Get-Process r5apex_dx12 -EA 0
if ($g) { $L.Add("GAME alive pid=$($g.Id) ws=$([int]($g.WorkingSet64/1MB))MB") } else { $L.Add('GAME gone') }
$L.Add('drv=' + ((Get-CimInstance Win32_SystemDriver -EA 0 |
    Where-Object { $_.Name -match 'gio|gdrv' } | ForEach-Object { "$($_.Name):$($_.State):$($_.Started)" }) -join ','))
$ns = @(Get-Content -LiteralPath $nl -EA 0 | Where-Object { $_.Trim() -and -not $_.StartsWith('#') } | ForEach-Object { $_.Trim() })
$L.Add('needles=' + $ns.Count + ' [' + ($ns -join ' | ') + ']')
$L.Add('p46 amp: pipeline matched own text 4/4 at top, 525 MB/s, full map desc ~60 s')
$L.Add('variable=needle_set dir=desc max_s=120 page_cap=1 max_hits=' + (100 * [Math]::Max(1, $ns.Count)))
$L.Add('playerscan sha256=' + (Get-FileHash -LiteralPath (Join-Path $repo 'ext\playerscan.py') -Algorithm SHA256).Hash)
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
if (-not $g) { Add-Content -LiteralPath $o -Value 'ABORT game gone'; exit 2 }
if ($ns.Count -lt 2) { Add-Content -LiteralPath $o -Value 'ABORT need >=2 needles'; exit 4 }
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p47_run.ps1'
Add-Content -LiteralPath $o -Value ('LAUNCHED pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o
