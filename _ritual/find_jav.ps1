$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\find_jav.txt'
'=== files matching javelin/eaanticheat/eac across program dirs (depth 4) ===' | Set-Content -LiteralPath $out
$roots = 'C:\Program Files (x86)', 'C:\Program Files', 'C:\ProgramData', 'C:\Users\New User\AppData\Local', 'C:\Users\New User\AppData\Roaming'
foreach ($r in $roots) {
  Get-ChildItem -LiteralPath $r -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '(?i)javelin|eaanticheat|eaac|eacef|anti.?cheat' } |
    Select-Object FullName, Length, LastWriteTime |
    Format-Table -Auto |
    Out-String -Width 300 |
    Add-Content -LiteralPath $out
}

'=== services / drivers matching anticheat ===' | Add-Content -LiteralPath $out
(Get-CimInstance Win32_Service | Where-Object { $_.PathName -match '(?i)anticheat|javelin|eac' } | Select-Object Name, DisplayName, State, StartMode, PathName | Format-List | Out-String -Width 300) | Add-Content -LiteralPath $out

'=== drivers dir: any anticheat / non-MS sys files ===' | Add-Content -LiteralPath $out
(Get-ChildItem -LiteralPath 'C:\Windows\System32\drivers' -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)eac|eaac|javelin|apex|gdrv|msio|ctiio|winring' } | Select-Object Name, Length, LastWriteTime | Format-Table -Auto | Out-String -Width 250) | Add-Content -LiteralPath $out

'=== log-ish files touched today under the game + programdata + appdata ===' | Add-Content -LiteralPath $out
foreach ($r in 'C:\Program Files\EA Games\Apex', 'C:\ProgramData', 'C:\Users\New User\AppData\Local', 'C:\Users\New User\AppData\Roaming', 'C:\Users\New User\Documents') {
  Get-ChildItem -LiteralPath $r -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue -Include '*.log', '*.txt', '*.json', '*.ini', '*.cfg', '*.dmp' |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-6) } |
    Select-Object FullName, Length, LastWriteTime |
    Format-Table -Auto |
    Out-String -Width 300 |
    Add-Content -LiteralPath $out
}

'=== Application/System events today from anticheat providers ===' | Add-Content -LiteralPath $out
(Get-WinEvent -FilterHashtable @{ LogName = 'Application', 'System'; StartTime = (Get-Date).Date } -ErrorAction SilentlyContinue |
  Where-Object { $_.ProviderName -match '(?i)anticheat|javelin|eac|EasyAnti|Application Error|Application Hang' } |
  Select-Object TimeCreated, ProviderName, Id, @{ n = 'Msg'; e = { ($_.Message -split "`r?`n")[0] } } |
  Format-Table -Auto | Out-String -Width 300) | Add-Content -LiteralPath $out

'=== full EAAntiCheat.cfg as printable strings, plus its header/type ===' | Add-Content -LiteralPath $out
$cfg = 'C:\Program Files\EA Games\Apex\EAAntiCheat.cfg'
$fi = Get-Item -LiteralPath $cfg
("size={0} lastwrite={1}" -f $fi.Length, $fi.LastWriteTime) | Add-Content -LiteralPath $out
$raw = [IO.File]::ReadAllBytes($cfg)
(([regex]::Matches([Text.Encoding]::GetEncoding(28591).GetString($raw), '[\x20-\x7E]{4,}') | ForEach-Object { $_.Value }) -join ' | ') | Add-Content -LiteralPath $out

'=== Apex folder: full listing (recursive) ===' | Add-Content -LiteralPath $out
(Get-ChildItem -LiteralPath 'C:\Program Files\EA Games\Apex' -Recurse -Force -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -Auto | Out-String -Width 300) | Add-Content -LiteralPath $out

'=== ProgramData\eaanticheat tree + any log content ===' | Add-Content -LiteralPath $out
(Get-ChildItem -LiteralPath 'C:\ProgramData\eaanticheat' -Recurse -Force -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -Auto | Out-String -Width 300) | Add-Content -LiteralPath $out

'DONE ' + (Get-Date) | Add-Content -LiteralPath $out
