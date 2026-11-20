# go11_watch2 - long-horizon seam autopilot (v2: 60 min, max 2 armings).
# Fires go11_arm_3.ps1 when our qk python pair retires; keeps hunting FEED_LIVE.
# State: temp\watch2_now.txt, events: temp\watch2_events.log, kill: watch2_stop.txt
$repo='C:\Users\New User\OneDrive\Desktop\cheating'
$now=Join-Path $repo 'temp\watch2_now.txt'
$ev =Join-Path $repo 'temp\watch2_events.log'
$LIFE=Join-Path $repo 'temp\go11_arm_3.txt'
"V2LIFT "+(Get-Date -Format 'HH:mm:ss') | Add-Content -LiteralPath $ev
$armed=0
for($i=0; $i -lt 1750; $i++){
  if(Test-Path (Join-Path $repo 'temp\watch2_stop.txt')){ "STOPFILE" | Add-Content -LiteralPath $ev; break }
  $stamp=Get-Date -Format 'HH:mm:ss'
  $feed=Get-Item (Join-Path $repo 'temp\qk_feed.json') -EA SilentlyContinue
  $feedAge = if($feed){ [math]::Round(((Get-Date)-$feed.LastWriteTime).TotalSeconds,1) } else { -1 }
  $feedSz  = if($feed){ $feed.Length } else { 0 }
  # 19/11: arming decision counts PRODUCERS only.  Consumers (qk_live) are pure
  # JSON-file readers - no gdrv3 handle, no contention - so a bridge consumer
  # staying alive must not block or abort rearming.
  $mine=@(Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'qk_va\.py' })
  $state='?'
  if($feed -and $feedAge -lt 8){ $state='FEED_LIVE' }
  elseif($mine.Count -eq 0){ $state='IDLE_CAN_ARM' }
  else{ $state=('RUNNING n={0}' -f $mine.Count) }
  ("{0} i={1} st={2} feedAge={3} feedSz={4} armed={5}" -f $stamp,$i,$state,$feedAge,$feedSz,$armed) | Set-Content -LiteralPath $now
  if($state -eq 'IDLE_CAN_ARM' -and $armed -lt 2){
    $armed++
    "EVENT [$stamp] producer retirement sighted -> arm #$armed (go11_arm_3)" | Add-Content -LiteralPath $ev
    & (Join-Path $repo 'temp\go11_arm_3.ps1') | Out-Null
    $vj = Get-Content -LiteralPath $LIFE -EA SilentlyContinue | Select-Object -Last 1
    "EVENT [$stamp] arm3 verdict: $vj" | Add-Content -LiteralPath $ev
    Start-Sleep -Seconds 8        # let the new pair register before next census
  }
  if($state -eq 'FEED_LIVE'){ "EVENT [$stamp] FEED LIVE sz=$feedSz age=$feedAge" | Add-Content -LiteralPath $ev; break }
  Start-Sleep -Seconds 2
}
"V2END "+(Get-Date -Format 'HH:mm:ss')+" armed=$armed" | Add-Content -LiteralPath $ev
exit 0
