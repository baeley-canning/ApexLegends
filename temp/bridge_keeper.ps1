# bridge_keeper - 19/11: guarantee no dark screen while awaiting qk_feed.json.
# Every 30 s: if FEED ABSENT and NO qk_live consumer alive -> spawn a fresh
# 1800 s bridge. Exits on feed birth (drawer-on-duty then owns the visual),
# on temp\keeper_stop.txt, or after 60 iterations (30 min horizon).
# Limitation (accepted): a stale-but-present feed does not trigger respawn;
# feed freshness belongs to watcher-2 / round-2 arming, not to this keeper.
$t='C:\Users\New User\OneDrive\Desktop\cheating\temp'
$py="$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
$feed=Join-Path $t 'qk_feed.json'
$stop=Join-Path $t 'keeper_stop.txt'
$out=Join-Path $t 'live_bridge_out.txt'
$err=Join-Path $t 'live_bridge_err.txt'
$ev=Join-Path $t 'keeper_log.txt'
$jn=Join-Path $t 'keeper_now.txt'
('KEEPER_LIFT '+(Get-Date -Format 'HH:mm:ss')) | Set-Content -LiteralPath $ev
for($i=0; $i -lt 60; $i++){
  if(Test-Path -LiteralPath $stop){
    'KEEPER_STOPFILE' | Add-Content -LiteralPath $ev
    break
  }
  if(Test-Path -LiteralPath $feed){
    ('KEEPER_EXIT feed_birth i='+$i) | Add-Content -LiteralPath $ev
    break
  }
  $cons=@(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'qk_live\.py' })
  if($cons.Count -eq 0){
    $pa = '-u "{0}" --from-feed --seconds=1800' -f (Join-Path 'C:\Users\New User\OneDrive\Desktop\cheating' 'ext\qk_live.py')
    $b=Start-Process -FilePath $py -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -ArgumentList $pa
    ('RESPAWN i='+$i+' pid='+$b.Id+' '+(Get-Date -Format 'HH:mm:ss')) | Add-Content -LiteralPath $ev
  }
  (('now i={0} cons={1} feed={2} {3}' -f $i,$cons.Count,(Test-Path -LiteralPath $feed),(Get-Date -Format 'HH:mm:ss'))) |
    Set-Content -LiteralPath $jn
  Start-Sleep -Seconds 30
}
('KEEPER_END '+(Get-Date -Format 'HH:mm:ss')) | Add-Content -LiteralPath $ev
