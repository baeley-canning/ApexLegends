# p46 pre-state (R3) + elevated stage.  VARIABLE = a needle that must exist in
# populated RAM: "r5apex" against the live game, descending from ram_top so the
# first GiB is user/kernel working set, not the dead low 1.5 GiB.  Pure read.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p46_pre.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$g = Get-Process r5apex_dx12 -EA 0
if ($g) { $L.Add("GAME alive pid=$($g.Id) ws=$([int]($g.WorkingSet64/1MB))MB") } else { $L.Add('GAME gone') }
$L.Add('drv=' + ((Get-CimInstance Win32_SystemDriver -EA 0 |
    Where-Object { $_.Name -match 'gio|gdrv' } | ForEach-Object { "$($_.Name):$($_.State):$($_.Started)" }) -join ','))
$L.Add('p45 result: pipeline ran, window 0x1000000..0x4000000 dead (bad4k=7522/7680) -> needs populated window')
$L.Add('variable=needle_value needle=r5apex dir=desc max_s=30 max_hits=4')
$L.Add('playerscan sha256=' + (Get-FileHash -LiteralPath (Join-Path $repo 'ext\playerscan.py') -Algorithm SHA256).Hash)
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
if (-not $g) { Add-Content -LiteralPath $o -Value 'ABORT game gone'; exit 2 }
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p46_run.ps1'
Add-Content -LiteralPath $o -Value ('LAUNCHED pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o
