# go11_arm_2 - fix of go11_arm_1: Start-Process -ArgumentList as ARRAY strips
# quotes around items with spaces ("New User"), so python argv split and both
# children died <1s. v2 passes ONE pre-quoted string. Same contract otherwise.
$repo='C:\Users\New User\OneDrive\Desktop\cheating'
$py="$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
$j=Join-Path $repo 'temp\go11_arm_2.txt'
"WAKE "+(Get-Date -Format 'HH:mm:ss') | Set-Content -LiteralPath $j
$g=@(Get-Process r5apex_dx12 -EA SilentlyContinue)
"RCOUNT=$($g.Count)" | Add-Content -LiteralPath $j
if($g.Count -eq 0){ "VERDICT: ABORT_NO_R5" | Add-Content -LiteralPath $j; exit 2 }
"RPID=$($g[0].Id)" | Add-Content -LiteralPath $j
Remove-Item -LiteralPath (Join-Path $repo 'temp\qk_feed.json') -Force -EA SilentlyContinue
$q={ '"{0}"' -f $args[0] }   # single-quote-wrap helper for spaced paths
$prodScript = Join-Path $repo 'ext\qk_va.py'
$consScript = Join-Path $repo 'ext\qk_live.py'
$prodArgs = '-u "{0}" --emit --hz=10 --secs=300' -f $prodScript
$consArgs = '-u "{0}" --from-feed --seconds=330' -f $consScript
"PRODARGS=$prodArgs" | Add-Content -LiteralPath $j
$p1=Start-Process -FilePath $py -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $repo 'temp\emit_out2.txt') `
    -RedirectStandardError   (Join-Path $repo 'temp\emit_err2.txt') `
    -ArgumentList $prodArgs
$p2=Start-Process -FilePath $py -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $repo 'temp\live_out2.txt') `
    -RedirectStandardError   (Join-Path $repo 'temp\live_err2.txt') `
    -ArgumentList $consArgs
"PGONE=$($p1.Id) PGINT=$($p2.Id)" | Add-Content -LiteralPath $j
Start-Sleep -Milliseconds 2500
"AFTER2S5 PROD_ALIVE=$(-not $p1.HasExited) CONS_ALIVE=$(-not $p2.HasExited)" | Add-Content -LiteralPath $j
"FEED_EXISTS=$(Test-Path (Join-Path $repo 'temp\qk_feed.json'))" | Add-Content -LiteralPath $j
"ARMED="+(Get-Date -Format 'HH:mm:ss') | Add-Content -LiteralPath $j
"VERDICT: ARMED_PAIR_GO11_2" | Add-Content -LiteralPath $j
exit 0