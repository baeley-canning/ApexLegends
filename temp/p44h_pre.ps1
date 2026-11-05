# p44h pre-state (R3).  Pure-read probe: device open only, no load/DSE/service touch.
# Variable under test: the decoy scan range.  The decoy trio is per-launch, so the
# p44f accept pass cannot run until decoyscan yields a live PA + stored pair.
# Records the transport, the game, the scan source hash and the WHEA high-water
# mark, then stages p44h_scan.ps1 elevated.  READ-ONLY.
$repo = 'C:\Users\New User\OneDrive\Desktop\cheating'
$o    = Join-Path $repo 'temp\p44h_pre.txt'
$L    = New-Object System.Collections.Generic.List[string]
$L.Add('now ' + (Get-Date -f 's'))
$L.Add('boot ' + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('s'))
$g = Get-Process -Id 17584 -EA 0
if ($g) { $L.Add("GAME alive pid=17584 ws=$([int]($g.WorkingSet64/1MB))MB started=$($g.StartTime.ToString('HH:mm:ss'))") }
else    { $L.Add('GAME gone pid=17584') }
$L.Add('eac procs=' + @(Get-Process | Where-Object { $_.Name -match 'EasyAnti' }).Count)
$L.Add('drv=' + ((Get-CimInstance Win32_SystemDriver -EA 0 |
    Where-Object { $_.Name -match 'gio|gdrv' } | ForEach-Object { "$($_.Name):$($_.State):$($_.Started)" }) -join ','))
$L.Add('ram_gb=' + [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1))
$L.Add('whea_since_boot=' + @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger' } -EA 0).Count)
$src = Join-Path $repo 'ext\decoyscan.py'
$L.Add('decoyscan sha256=' + (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash)
$L.Add('stale trio in basehunt: LINK=0x2481D60C0 FL=0xFFFFA401B25A5258 BL=0xFFFFA401B7EA0258 (previous launch pid 0x1570)')
$L.Add('prior p44f verdict=' + ((Select-String -LiteralPath (Join-Path $repo '_ritual\p44f_livedump.txt') -Pattern '^VERDICT: (.+)$' -EA 0 | Select-Object -Last 1).Matches[0].Groups[1].Value))
Set-Content -LiteralPath $o -Value $L -Encoding UTF8
if (-not $g) { Add-Content -LiteralPath $o -Value 'ABORT game gone'; exit 2 }
$r = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -ArgumentList `
     '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\Windows\Temp\p44h_scan.ps1', '--pid=17584', '--down=0x100000000', '--want=3', '--max-s=240'
Add-Content -LiteralPath $o -Value ('LAUNCHED pid=' + $r.Id + ' at ' + (Get-Date -f 'HH:mm:ss'))
Get-Content -LiteralPath $o
