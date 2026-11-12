# h319_live.ps1 - P0 passive liveness watch. NOTHING is injected; the driver is merely loaded.
# Samples every 10 s: game pid, Javelin kill events. Fresh output file per run (R5).
# Variable under test: game stability with apexdrv resident only.
param([int]$Minutes = 45)
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$n = 1; while (Test-Path (Join-Path $here ("h319_live{0}.out" -f $n))) { $n++ }
$out = Join-Path $here ("h319_live{0}.out" -f $n)
function Say([string]$s) { $line = (Get-Date -f 'HH:mm:ss.fff') + ' ' + $s; Write-Host $line; Add-Content -LiteralPath $out -Value $line }
$t0 = Get-Date
$drv = (@(sc.exe query apexdrv 2>&1) -join ' ') -match 'RUNNING'
$mode = if ($drv) { 'driver RESIDENT' } else { 'driver NOT loaded' }
Say ('===== h319 live watch r' + $n + ' - ' + $mode + ', no inject =====')
function JavCount { @(Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='EA Javelin Anticheat'; StartTime=$t0} -EA 0).Count }
$seenPid = 0
$polls = [int]($Minutes * 6)
for ($i = 0; $i -lt $polls; $i++) {
  $p = @(Get-Process r5apex_dx12 -EA 0)
  if ($p.Count -gt 0) {
    if ($seenPid -eq 0) { $seenPid = $p[0].Id; Say ('ALIVE pid=' + $seenPid + ' start=' + $p[0].StartTime.TimeOfDay.ToString('hh\:mm\:ss') + ' jav=' + (JavCount)) }
    elseif (($i % 6) -eq 0) { Say ('tick pid=' + $p[0].Id + ' jav=' + (JavCount)) }
  } else {
    if ($seenPid -ne 0) {
      $p2 = @(Get-Process r5apex_dx12 -EA 0)
      if ($p2.Count -eq 0) {
        Start-Sleep -Seconds 2
        if (@(Get-Process r5apex_dx12 -EA 0).Count -eq 0) {
          $ev = @(Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='EA Javelin Anticheat'; StartTime=$t0} -EA 0)
          $last = if ($ev.Count) { $ev[0].TimeCreated.ToString('HH:mm:ss') } else { 'NONE' }
          $alive = ((Get-Date) - $t0).TotalSeconds
          Say ('DEAD pid=' + $seenPid + ' javelin_events=' + $ev.Count + ' last_javelin=' + $last)
          if ($last -ne 'NONE') { Say 'RESULT: DIED - Javelin kill event present'; Say ('VERDICT: game died with ' + $mode + ', javelin fired (' + $last + ')') }
          else { Say 'RESULT: DIED - no Javelin event'; Say ('VERDICT: game died with ' + $mode + ', no Javelin kill event (crash, not AC)') }
          return
        }
      }
    }
  }
  Start-Sleep -Seconds 10
}
if ($seenPid) { Say ('RESULT: SURVIVED ' + $Minutes + ' min, pid=' + $seenPid); Say ('VERDICT: ' + $mode + ' is tolerated this session (no kill in ' + $Minutes + ' min)') }
else { Say 'RESULT: NO GAME started during watch' }
