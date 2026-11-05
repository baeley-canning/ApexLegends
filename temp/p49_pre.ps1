# p49 pre-state (R3) + elevated stage.  VARIABLE = match_mode tuning.
# Needles from temp\p49_needles.txt -- one scoreboard name per line.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p49_pre.txt'
$nl   = Join-Path $repo 'temp\p49_needles.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$g = Get-Process r5apex_dx12 -EA 0
if ($g) { $L.Add("GAME alive pid=$($g.Id) ws=$([int]($g.WorkingSet64/1MB))MB") } else { $L.Add('GAME gone') }
$L.Add('drv=' + ((Get-CimInstance Win32_SystemDriver -EA 0 |
    Where-Object { $_.Name -match 'gio|gdrv' } | ForEach-Object { "$($_.Name):$($_.State):$($_.Started)" }) -join ','))
$L.Add('map: single range 0x140000000-0x800000000; noise band at 0x7ff3.... was our console')
$L.Add('variable=scan_mode window=0x0eda00000..0x7eda00000 per_needle=1200 ctx=64')
$L.Add('per_needle instead of max_hits so hitting the cap cannot truncate the sweep (p49 dry: stopped=max_hits at 12247/27354 MiB)')
$L.Add('playerscan sha256=' + (Get-FileHash -LiteralPath (Join-Path $repo 'ext\playerscan.py') -Algorithm SHA256).Hash)
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
if (-not $g) { Add-Content -LiteralPath $o -Value 'ABORT game gone'; exit 2 }
if (-not (Test-Path -LiteralPath $nl)) { Add-Content -LiteralPath $o -Value 'ABORT needles file missing'; exit 4 }
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p49_run.ps1'
Add-Content -LiteralPath $o -Value ('LAUNCHED pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o
