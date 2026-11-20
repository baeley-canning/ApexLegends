# go11_arm_1 - arm the PLAN-item-2 feed pair the moment r5apex_dx12 exists.
# Called ONLY after a successful recon shows RCOUNT>=1, so this script contains
# NO wait loop and finishes in ~1 s (survives the degraded console capture).
# Journal: temp\go11_arm_1.txt  (R3: file is the verdict channel)
$repo='C:\Users\New User\OneDrive\Desktop\cheating'
$py="$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
$j=Join-Path $repo 'temp\go11_arm_1.txt'
"WAKE "+(Get-Date -Format 'HH:mm:ss') | Set-Content -LiteralPath $j
$g=@(Get-Process r5apex_dx12 -EA SilentlyContinue)
"RCOUNT=$($g.Count)" | Add-Content -LiteralPath $j
if($g.Count -eq 0){ "VERDICT: ABORT_NO_R5" | Add-Content -LiteralPath $j; exit 2 }
"RPID=$($g[0].Id)" | Add-Content -LiteralPath $j
# pre-arm feed hygiene: remove any stale seed so consumer sees only fresh data
Remove-Item -LiteralPath (Join-Path $repo 'temp\qk_feed.json') -Force -EA SilentlyContinue
# producer: PLAN prescribes --emit --hz=10 --secs=300; DTB discovery ~70-80s lands in menus
$p1=Start-Process -FilePath $py -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $repo 'temp\emit_out.txt') `
    -RedirectStandardError   (Join-Path $repo 'temp\emit_err.txt') `
    -ArgumentList @('-u',(Join-Path $repo 'ext\qk_va.py'),'--emit','--hz=10','--secs=300')
# consumer: runs 330s so it drains the producer's final second before emitter exit
$p2=Start-Process -FilePath $py -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $repo 'temp\live_out.txt') `
    -RedirectStandardError   (Join-Path $repo 'temp\live_err.txt') `
    -ArgumentList @('-u',(Join-Path $repo 'ext\qk_live.py'),'--from-feed','--seconds=330')
"PGONE=$($p1.Id) PGINT=$($p2.Id)" | Add-Content -LiteralPath $j
Start-Sleep -Milliseconds 800
"AFTER1S PROD_ALIVE=$(-not $p1.HasExited) CONS_ALIVE=$(-not $p2.HasExited)" | Add-Content -LiteralPath $j
"ARMED="+(Get-Date -Format 'HH:mm:ss') | Add-Content -LiteralPath $j
"VERDICT: ARMED_PAIR_GO11_1" | Add-Content -LiteralPath $j
exit 0