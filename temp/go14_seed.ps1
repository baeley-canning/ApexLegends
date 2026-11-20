# go14_seed - re-proof of the file-feed overlay leg on TODAY's environment.
# Exactly the 19/11 19:53 smoke, replayed: parked seed -> fresh ts -> qk_feed.json;
# qk_live --from-feed --seconds=60 consumes it. Expected: 8 candidates, ~4 visible
# boxes, ~55+ fps, VERDICT PARTIAL (R9) - consumer proof only (FACTS 19/11 row).
# Hygiene afterwards: qk_feed.json removed (seed stays parked untouched).
$repo='C:\Users\New User\OneDrive\Desktop\cheating'
$t =Join-Path $repo 'temp'
$py="$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
$j =Join-Path $t 'go14_seed.txt'
'WAKE '+(Get-Date -Format 'HH:mm:ss') | Set-Content -LiteralPath $j
$src=Join-Path $t '_smoke_seed_backup.json'
if(-not (Test-Path -LiteralPath $src)){ 'VERDICT: ABORT_NO_SEED_BACKUP' | Add-Content -LiteralPath $j; exit 2 }
# patch ts so STALE_FEED(0.5 s) treats it as newborn at consumer start.
# BOM-LESS utf-8 via .NET: Set-Content -Encoding UTF8 emits a BOM that kills
# json.loads in qk_live (JSONDecodeError - found 20/11 11:39 leg).
$raw=Get-Content -LiteralPath $src -Raw | ConvertFrom-Json
$raw.ts=[double]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())/1000.0
$raw.meta.producer='smoke-seed-go14'
$txt=$raw | ConvertTo-Json -Depth 12 -Compress
[IO.File]::WriteAllText((Join-Path $t 'qk_feed.json'), $txt, [Text.UTF8Encoding]::new($false))
'FEED_WRITTEN='+((Get-Item (Join-Path $t 'qk_feed.json')).Length)+' B' | Add-Content -LiteralPath $j
# R3 precheck: the file must parse BOM-less and carry a sane entity set BEFORE
# any consumer is armed; a corrupt feed otherwise burns a 60 s arm silently.
$pc = & $py -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); n=len(d.get('ents') or d.get('records') or []); print('PRECHECK_ENTS=%d'%n); sys.exit(0 if n>=8 else 3)" (Join-Path $t 'qk_feed.json')
"$pc" | Add-Content -LiteralPath $j
if($LASTEXITCODE -ne 0){ 'VERDICT: ABORT_PRECHECK_FAIL' | Add-Content -LiteralPath $j; exit 3 }
# ts-cadencer: from-feed drops boxes when rec.ts is older than 0.5 s
# (STALE_FEED), so the seed must ride a producer heartbeat for the window.
# 65 s (> consumer's 60 s) then dies naturally.
$r=Start-Process -FilePath $py -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $t 'refresh_out.txt') `
    -RedirectStandardError   (Join-Path $t 'refresh_err.txt') `
    -ArgumentList ('-u "{0}" 65' -f (Join-Path $t 'go14_refresh.py'))
'REFR_PID='+$r.Id | Add-Content -LiteralPath $j
$c=Start-Process -FilePath $py -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $t 'live_seed_out.txt') `
    -RedirectStandardError   (Join-Path $t 'live_seed_err.txt') `
    -ArgumentList ('-u "{0}" --from-feed --seconds=60' -f (Join-Path $repo 'ext\qk_live.py'))
'CONS_PID='+$c.Id | Add-Content -LiteralPath $j
Start-Sleep -Seconds 3
'AFTER3S CONS_ALIVE='+(-not $c.HasExited) | Add-Content -LiteralPath $j
"ARMED="+(Get-Date -Format 'HH:mm:ss')+" (drain ~60 s; read live_seed_out.txt tail afterwards)" | Add-Content -LiteralPath $j
'VERDICT: SEEDED_CONSUMER_ARMED_GO14' | Add-Content -LiteralPath $j
exit 0