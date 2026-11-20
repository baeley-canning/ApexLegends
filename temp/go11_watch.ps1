# go11_watch - autonomous seam-watcher (R3: state only in files).
# Loop 2s x max 720 (24 min). Writes live state to temp\watch_now.txt,
# event log to temp\watch_events.log (append). Exits on feed-live, stop-file,
# or exhaustion. Fires go11_arm_3.ps1 exactly once on pair-retirement.
$repo='C:\Users\New User\OneDrive\Desktop\cheating'
$now=Join-Path $repo 'temp\watch_now.txt'
$ev =Join-Path $repo 'temp\watch_events.log'
"LIFT "+(Get-Date -Format 'HH:mm:ss') | Add-Content -LiteralPath $ev
for($i=0; $i -lt 720; $i++){
  if(Test-Path (Join-Path $repo 'temp\watch_stop.txt')){ "STOPFILE" | Add-Content $ev; break }
  $stamp=Get-Date -Format 'HH:mm:ss'
  $feed=Get-Item (Join-Path $repo 'temp\qk_feed.json') -EA SilentlyContinue
  $feedAge = if($feed){ [math]::Round(((Get-Date)-$feed.LastWriteTime).TotalSeconds,1) } else { -1 }
  $feedSz  = if($feed){ $feed.Length } else { 0 }
  $mine=@(Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'qk_(va|live)\.py' })
  $state='?'
  if($feed -and $feedAge -lt 6){ $state='FEED_LIVE' }
  elseif($mine.Count -eq 0){ $state='ALL_DEAD_WOULD_ARM' }
  elseif($mine.Count -ge 1){ $state=('RUNNING n={0}' -f $mine.Count) }
  ("{0} i={1} st={2} feedAge={3} feedSz={4} mine={5}" -f $stamp,$i,$state,$feedAge,$feedSz,$mine.Count) | Set-Content -LiteralPath $now
  # handoff trigger: producer retired (11932-specific or generically none-left-running)
  if($mine.Count -eq 0 -and $state -ne 'FEED_LIVE'){
    "EVENT [$stamp] pair retired -> invoking go11_arm_3" | Add-Content -LiteralPath $ev
    & (Join-Path $repo 'temp\go11_arm_3.ps1') | Out-Null
    $vj=Get-Content (Join-Path $repo 'temp\go11_arm_3.txt') -EA SilentlyContinue | Select-Object -Last 1
    "EVENT [$stamp] arm3 verdict: $vj" | Add-Content -LiteralPath $ev
  }
  if($state -eq 'FEED_LIVE'){ "EVENT [$stamp] FEED LIVE sz=$feedSz" | Add-Content -LiteralPath $ev; break }
  Start-Sleep -Seconds 2
}
"END "+(Get-Date -Format 'HH:mm:ss') | Add-Content -LiteralPath $ev
exit 0
