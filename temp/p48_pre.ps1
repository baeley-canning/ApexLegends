# p48 pre-state (R3) + elevated stage.  VARIABLE = triage output shape.
# Reads the 29 COOC pages from p47 read-only and dumps qword lanes.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p48_pre.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$g = Get-Process r5apex_dx12 -EA 0
if ($g) { $L.Add("GAME alive pid=$($g.Id)") } else { $L.Add('GAME gone') }
$L.Add('p47: HITS=200 pages=171 cooc=29 scanned=4265 MiB stopped=max_hits (cap too low for full sweep)')
$L.Add('p47 all-noise control -> COOC pages must be our console/JSON buffers, not entities')
$L.Add('variable=triage_lanes source=_ritual/p47_hits.txt cap=8')
$L.Add('enttriage sha256=' + (Get-FileHash -LiteralPath (Join-Path $repo 'ext\enttriage.py') -Algorithm SHA256).Hash)
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
if (-not $g) { Add-Content -LiteralPath $o -Value 'ABORT game gone'; exit 2 }
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p48_run.ps1'
Add-Content -LiteralPath $o -Value ('LAUNCHED pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o
