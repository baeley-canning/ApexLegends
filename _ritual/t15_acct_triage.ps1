# t15_acct_triage.ps1 - READ-ONLY ban triage. No driver, no service, no elevation.
# Decides account-ban vs device-ban and locates where this box stores EA account
# identity (so evidence files can be stamped with it from now on).
# Output: _ritual/_t15_triage.txt   Verdict names the variable.
$ErrorActionPreference = 'SilentlyContinue'
$root = 'C:\Users\New User\OneDrive\Desktop\cheating'
$out  = Join-Path $root '_ritual\_t15_triage.txt'
$L = New-Object System.Collections.ArrayList
function W($s) { [void]$L.Add("$s") }
function Sec($s) { W ''; W "##### $s #####" }
function Cap($p, $n = 12) {
  if (Test-Path -LiteralPath $p) {
    $f = Get-Item -LiteralPath $p
    W ("  file {0}  {1} B  {2}" -f $f.Name, $f.Length, $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
    if ($f.Length -lt 4MB) { Get-Content -LiteralPath $p -TotalCount $n | ForEach-Object { W ("  | " + $_) } }
  } else { W "  absent: $p" }
}

W "t15 account/ban triage  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W ("host={0} user={1}" -f $env:COMPUTERNAME, $env:USERNAME)

Sec '1. launchers + game processes'
foreach ($n in 'EADesktop','EAapp','EABackgroundService','Origin','r5apex_dx12','r5apex','start_protected_game','EAAntiCheatService') {
  $p = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
  W ("  {0,-22} {1}" -f $n, $(if ($p) { 'RUNNING pid=' + ($p.Id -join ',') } else { '-' }))
}
W ("  EA app exe: " + (Get-ChildItem 'C:\Program Files\Electronic Arts\EA Desktop\EADesktop.exe','C:\Program Files (x86)\Electronic Arts\EA Desktop\EADesktop.exe' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName + ' ' + $_.VersionInfo.FileVersion }))
W ("  game exe: " + (Get-ChildItem 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName + '  ' + $_.Length + ' B  ' + $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }))

Sec '2. account identity stored on this box (Saved Games / profile)'
$sg = Join-Path $env:USERPROFILE 'Saved Games\Respawn\Apex'
W "  dir exists: $($null -ne (Get-Item -LiteralPath $sg))"
Get-ChildItem -LiteralPath $sg -Recurse -File -Depth 2 -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 25 |
  ForEach-Object { W ("  {0,-46} {1,9} B  {2}" -f $_.FullName.Substring($sg.Length), $_.Length, $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) }
Cap (Join-Path $sg 'profile\profile.cfg') 20
Cap (Join-Path $sg 'local\settings.cfg') 8

Sec '3. EA app local state (where the session/EAID lives)'
foreach ($d in (Join-Path $env:LOCALAPPDATA 'Electronic Arts'), 'C:\ProgramData\EA Desktop', (Join-Path $env:APPDATA 'EA Desktop')) {
  W "  -- $d"
  if (Test-Path -LiteralPath $d) {
    Get-ChildItem -LiteralPath $d -Depth 1 -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 18 |
      ForEach-Object { W ("     {0,-40} {1,10} {2}" -f $_.Name, $(if ($_.PSIsContainer) { '<dir>' } else { $_.Length }), $_.LastWriteTime.ToString('MM-dd HH:mm')) }
  } else { W '     absent' }
}

Sec '4. ban / enforcement strings in EA app logs'
$logs = @()
foreach ($d in 'C:\ProgramData\EA Desktop\Logs', (Join-Path $env:LOCALAPPDATA 'Electronic Arts\EA Desktop\Logs')) {
  if (Test-Path -LiteralPath $d) { $logs += @(Get-ChildItem -LiteralPath $d -Recurse -File -Include *.log,*.txt -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 12) }
}
W ("  log files considered: {0}" -f $logs.Count)
foreach ($f in $logs) {
  $hit = @(Select-String -LiteralPath $f.FullName -Pattern 'ban','suspend','disabled','enforc','blocked','HWID','device' -SimpleMatch -ErrorAction SilentlyContinue)
  if ($hit.Count) {
    W ("  == {0}  ({1} hits)" -f $f.FullName, $hit.Count)
    $hit | Select-Object -Last 6 | ForEach-Object { W ("     {0}: {1}" -f $_.LineNumber, $_.Line.Trim().Substring(0, [Math]::Min(190, $_.Line.Trim().Length))) }
  }
}

Sec '5. registry (read-only)'
foreach ($k in 'HKCU:\Software\Electronic Arts', 'HKCU:\Software\EA Games') {
  W "  -- $k"
  if (Test-Path $k) { Get-ChildItem $k -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 15 | ForEach-Object { W ("     " + $_.Name) } } else { W '     absent' }
}

Sec '6. verdict inputs'
W '  A fresh account logging into THIS box with no cheat loaded is the control arm:'
W '  survives -> account ban (new account is enough).  dies again -> device/HWID or gdrv3 signature.'
[void]$L.Add("VERDICT: triage collected - read sections 2-4, do NOT start a driver")

$L -join "`r`n" | Out-File -LiteralPath $out -Encoding utf8
Write-Host "wrote $out"
