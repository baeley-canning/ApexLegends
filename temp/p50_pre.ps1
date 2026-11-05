# p50 pre-state (R3) + elevated stage.  VARIABLE = real scoreboard names.
# Put 3-5 distinct in-match player names in temp\p50_needles.txt first.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p50_pre.txt'
$nl   = Join-Path $repo 'temp\p50_needles.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$g = Get-Process r5apex_dx12 -EA 0
if ($g) { $L.Add("GAME alive pid=$($g.Id) ws=$([int]($g.WorkingSet64/1MB))MB") } else { $L.Add('GAME gone') }
$L.Add('drv=' + ((Get-CimInstance Win32_SystemDriver -EA 0 |
    Where-Object { $_.Name -match 'gio|gdrv' } | ForEach-Object { "$($_.Name):$($_.State):$($_.Started)" }) -join ','))
$L.Add('variable=needle_source real scoreboard names; scan window unchanged 0x0eda00000..0x7eda00000')
$L.Add('p49 proved full-window completion (stopped=covered 27354 MiB, sat 1200/1200/1200) so the sweep cannot truncate')
$L.Add('needles file: ' + $(if (Test-Path -LiteralPath $nl) { (Get-Content -LiteralPath $nl | Where-Object { $_.Trim() -and -not $_.StartsWith('#') }) -join ' | ' } else { 'MISSING' }))
$L.Add('playerscan sha256=' + (Get-FileHash -LiteralPath (Join-Path $repo 'ext\playerscan.py') -Algorithm SHA256).Hash)
$L.Add('enttriage sha256=' + (Get-FileHash -LiteralPath (Join-Path $repo 'ext\enttriage.py') -Algorithm SHA256).Hash)
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
if (-not $g) { Add-Content -LiteralPath $o -Value 'ABORT game gone'; exit 2 }
if (-not (Test-Path -LiteralPath $nl)) { Add-Content -LiteralPath $o -Value 'ABORT needles file missing'; exit 4 }
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p50_run.ps1'
Add-Content -LiteralPath $o -Value ('LAUNCHED pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o
