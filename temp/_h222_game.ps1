# _h222_game.ps1 - start Apex via the EA Desktop protocol route and wait for r5apex_dx12.
# No state mutated; own log; poll only. Caller reads the log (terminal output unreliable).
$log = Join-Path $PSScriptRoot '_h222_game.txt'
function W($s) { ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $s) | Add-Content -LiteralPath $log -Encoding UTF8 }
W ('START up=' + [int]((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalMinutes + 'min')
W ('pre drv=' + (((& sc.exe query apexdrv | Select-String 'STATE') -replace '\s+', ' ').Trim()))
$ea = @(
    'C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\EALauncher.exe'
    'C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1
$uri = 'origin2://game/launch/?offerIds=194908&title=Apex%u0020Legends%u2122&authCode=&cmdParams='
if ($ea) { W ('spawn ' + $ea); Start-Process -FilePath $ea -ArgumentList ('"' + $uri + '"') }
else { W 'spawn via URI handler'; Start-Process $uri }
$p = $null
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 3
    $n = @(Get-Process r5apex_dx12 -EA 0)
    if ($n.Count) { $p = $n[0]; W ('GAME pid=' + $p.Id + ' at +' + (($i + 1) * 3) + 's'); break }
    if (($i + 1) % 5 -eq 0) { W ('wait +' + (($i + 1) * 3) + 's ea=' + @(Get-Process EADesktop, EALauncher, EAAntiCheat.GameServiceLauncher -EA 0).Count) }
}
if (-not $p) { W 'RESULT: FAIL no r5apex_dx12 within 180 s'; exit 1 }
Start-Sleep -Seconds 5
W ('snap ac=' + ((Get-Process EAAntiCheat.GameServiceLauncher, EasyAntiCheat_EOS -EA 0 | ForEach-Object { $_.Name + ':' + $_.Id }) -join ','))
W ('snap title=' + $p.MainWindowTitle + ' ws=' + [int]($p.WorkingSet64 / 1MB) + 'MB')
W 'RESULT: GAME UP'
