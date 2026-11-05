# p45 pre-state (R3) + elevated stage.  VARIABLE = the needle pipeline itself:
# playerscan.py on a needle that is guaranteed present ("drivers"), tiny window,
# own OUT.  Pure read.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p45_pre.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$g = Get-Process r5apex_dx12 -EA 0
if ($g) { $L.Add("GAME alive pid=$($g.Id)") } else { $L.Add('GAME gone') }
$L.Add('eac procs=' + @(Get-Process | Where-Object { $_.Name -match 'EasyAnti' }).Count)
$L.Add('drv=' + ((Get-CimInstance Win32_SystemDriver -EA 0 |
    Where-Object { $_.Name -match 'gio|gdrv' } | ForEach-Object { "$($_.Name):$($_.State):$($_.Started)" }) -join ','))
$L.Add('variable=needle_pipeline needle=drivers window=0x1000000..0x4000000 dir=asc max_hits=6')
$L.Add('playerscan sha256=' + (Get-FileHash -LiteralPath (Join-Path $repo 'ext\playerscan.py') -Algorithm SHA256).Hash)
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p45_run.ps1'
Add-Content -LiteralPath $o -Value ('LAUNCHED pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o
