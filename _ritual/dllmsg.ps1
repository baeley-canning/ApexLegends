$out = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\jav_phrases.txt'
$targets = @(
  'C:\Program Files\EA Games\Apex\EAAntiCheat.GameServiceLauncher.exe',
  'C:\Program Files\EA Games\Apex\EAAntiCheat.GameServiceLauncher.dll',
  'C:\Program Files\EA Games\Apex\preloader_l.dll'
)
$kw = '(?i)(driver|sign|integrity|polic|tamper|virtual|hyper|memory|config|enable|disable|boot|firmware|detect|violat|security|check|unaccept|restart|block|suspect)'

'=== sentence-like strings (>=14 chars, contains a space) filtered by keywords ===' | Set-Content -LiteralPath $out

foreach ($t in $targets) {
  if (-not (Test-Path -LiteralPath $t)) { "MISSING $t" | Add-Content -LiteralPath $out; continue }
  $raw = [IO.File]::ReadAllBytes($t)
  $as = [regex]::Matches([Text.Encoding]::GetEncoding(28591).GetString($raw), '[\x20-\x7E]{14,}') | ForEach-Object { $_.Value }
  $wd = [regex]::Matches([Text.Encoding]::Unicode.GetString($raw), '[\x20-\x7E]{14,}') | ForEach-Object { $_.Value }
  $phr = ($as + $wd) | Where-Object { $_ -match ' ' -and $_ -match $kw } | Sort-Object -Unique
  ('----- {0} : raw_ascii={1} raw_wide={2} phrases={3} -----' -f $t, $as.Count, $wd.Count, $phr.Count) | Add-Content -LiteralPath $out
  $phr | ForEach-Object { if ($_.Length -gt 220) { $_.Substring(0, 220) } else { $_ } } | Add-Content -LiteralPath $out
}

'DONE ' + (Get-Date) | Add-Content -LiteralPath $out
