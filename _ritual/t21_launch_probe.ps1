# t21_launch_probe.ps1 - click PLAY on the banned account and record what actually happens.
# READ-ONLY except the click; no driver, no service. Answers: does the ban block launch,
# or only matchmaking (range may still be usable).  Output _ritual/_t21_launch.txt
$ErrorActionPreference = 'SilentlyContinue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$out  = Join-Path $root '_ritual\_t21_launch.txt'
$L = New-Object System.Collections.ArrayList
function W($s) { [void]$L.Add("$s") }

W "t21 launch probe  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "account stamp before: $((Get-Content (Join-Path $root '_ritual\_account.txt') | Select-String 'ACTIVE_EAID|ACTIVE_BANNED') -join ' ')"
W ("pre procs: " + (@(Get-Process -Name 'r5apex_dx12','start_protected_game','EAAntiCheatService' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name + '=' + $_.Id }) -join ','))

& (Join-Path $root '_ritual\click.ps1') -X 1028 -Y 560 | Out-Null
W 'clicked PLAY at 1028,560'

$seen = @{}
for ($i = 0; $i -lt 60; $i++) {
  Start-Sleep -Seconds 1
  foreach ($n in 'start_protected_game','r5apex_dx12','EAAntiCheatService','r5apex') {
    Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object { if (-not $seen.ContainsKey($n)) { $seen[$n] = $true; W ("+{0,3}s  {1} pid={2}" -f $i, $n, $_.Id) } }
  }
  if ($seen.ContainsKey('r5apex_dx12') -and $i -gt 20) { break }
}
W ''
W ("seen: " + $(if ($seen.Count) { ($seen.Keys -join ',') } else { 'NOTHING' }))
Start-Sleep -Seconds 3
& (Join-Path $root '_ritual\shot_full.ps1') -Out (Join-Path $root '_ritual\_t21_after.png') | Out-Null
W ("post procs: " + (@(Get-Process -Name 'r5apex_dx12','start_protected_game' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name + '=' + $_.Id }) -join ','))
[void]$L.Add($(if ($seen.ContainsKey('r5apex_dx12')) { 'VERDICT: game process appeared - ban is past the launch stage, read the screenshot' } else { 'VERDICT: no game process in 60 s - launch itself is refused' }))

$L -join "`r`n" | Out-File -LiteralPath $out -Encoding utf8
Write-Host "wrote $out"
