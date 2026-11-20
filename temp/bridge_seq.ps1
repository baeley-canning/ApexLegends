# bridge_seq - 19/11: revive the visual layer + swap in the producers-only watcher.
$repo='C:\Users\New User\OneDrive\Desktop\cheating'
$py="$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
$jr=Join-Path $repo 'temp\bridge_launch.txt'
('BRIDGE_LAUNCH '+(Get-Date -Format 'HH:mm:ss')) | Set-Content -LiteralPath $jr
# 1) bridge consumer: overlay window over the game, reads qk_feed.json; heartbeats
#    until the feed births; 1500 s life to cover the remaining ladder + emission.
$pa = '-u "{0}" --from-feed --seconds=1500' -f (Join-Path $repo 'ext\qk_live.py')
$b=Start-Process -FilePath $py -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $repo 'temp\live_bridge_out.txt') `
    -RedirectStandardError   (Join-Path $repo 'temp\live_bridge_err.txt') `
    -ArgumentList $pa
('BRIDGE_PID='+$b.Id) | Add-Content -LiteralPath $jr
('ARGS='+$pa) | Add-Content -LiteralPath $jr
Start-Sleep -Seconds 2
('BRIDGE_ALIVE2S='+(-not $b.HasExited)) | Add-Content -LiteralPath $jr
'--- watcher swap ---' | Add-Content -LiteralPath $jr
# 2) retire watcher-v2-old (old regex), relaunch with producers-only census.
'STOP' | Set-Content -LiteralPath (Join-Path $repo 'temp\watch2_stop.txt')
Start-Sleep -Seconds 6
Get-Content (Join-Path $repo 'temp\watch2_events.log') -Tail 2 | Add-Content -LiteralPath $jr
Remove-Item -LiteralPath (Join-Path $repo 'temp\watch2_stop.txt') -Force
Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "C:\Users\New User\OneDrive\Desktop\cheating\temp\go11_watch2.ps1"'
('WATCH2_RELAUNCHED='+(Get-Date -Format 'HH:mm:ss')) | Add-Content -LiteralPath $jr
'SEQ_COMPLETE' | Add-Content -LiteralPath $jr
