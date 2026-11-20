# go11_arm_3 - LONG-COVER pair for the live match leg (round 2 after go11_arm_2's
# 300s plumbing-proof pair retires). Sequential guard: refuses to overlap any
# live qk_va/qk_lite python; only arms when census shows zero of ours running.
# Journal: temp\go11_arm_3.txt (R3 verdict channel)
$repo='C:\Users\New User\OneDrive\Desktop\cheating'
$py="$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
# 19/11: skip the PEB window-scan fallback inside qk_va discovery - it swept the
# full 27.7 GB tonight (1202 s) with no verdict while the player sat in a live
# match.  Round 2 goes: hits-cache -> EPROCESS candidates -> pml4 directly.
$env:QK_NO_PEB='1'
$j=Join-Path $repo 'temp\go11_arm_3.txt'
"WAKE "+(Get-Date -Format 'HH:mm:ss') | Set-Content -LiteralPath $j
# guard A: game must be alive
$g=@(Get-Process r5apex_dx12 -EA SilentlyContinue)
"RCOUNT=$($g.Count)" | Add-Content -LiteralPath $j
if($g.Count -eq 0){ "VERDICT: ABORT_NO_R5" | Add-Content -LiteralPath $j; exit 2 }
"RPID=$($g[0].Id)" | Add-Content -LiteralPath $j
# guard B: our PRODUCER python must have retired (19/11: producers only -
# consumers are file-readers and may legally persist as a visual bridge;
# gdrv3 contention is a producer-only property)
$mine=@(Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'qk_va\.py' })
"MINE_RUNNING=$($mine.Count)" | Add-Content -LiteralPath $j
foreach($m in $mine){ ("STILL_ALIVE PID=$($m.ProcessId) CMD=$($m.CommandLine)") | Add-Content -LiteralPath $j }
if($mine.Count -gt 0){ "VERDICT: ABORT_PAIR_STILL_LIVING" | Add-Content -LiteralPath $j; exit 3 }
# bonus: if an old DTB cache exists for THIS pid, discovery will be instant
$dtb=Join-Path $repo ("temp\qk_dtb_" + $g[0].Id + ".txt")
"DTB_CACHE=$(Test-Path $dtb)" | Add-Content -LiteralPath $j
Remove-Item -LiteralPath (Join-Path $repo 'temp\qk_feed.json') -Force -EA SilentlyContinue
$prodArgs = '-u "{0}" --emit --hz=10 --secs=1200' -f (Join-Path $repo 'ext\qk_va.py')
$consArgs = '-u "{0}" --from-feed --seconds=1260' -f (Join-Path $repo 'ext\qk_live.py')
"PRODARGS=$prodArgs" | Add-Content -LiteralPath $j
$p1=Start-Process -FilePath $py -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $repo 'temp\emit_out3.txt') `
    -RedirectStandardError   (Join-Path $repo 'temp\emit_err3.txt') `
    -ArgumentList $prodArgs
$p2=Start-Process -FilePath $py -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $repo 'temp\live_out3.txt') `
    -RedirectStandardError   (Join-Path $repo 'temp\live_err3.txt') `
    -ArgumentList $consArgs
"PGONE=$($p1.Id) PGINT=$($p2.Id)" | Add-Content -LiteralPath $j
Start-Sleep -Milliseconds 2500
"AFTER2S5 PROD_ALIVE=$(-not $p1.HasExited) CONS_ALIVE=$(-not $p2.HasExited)" | Add-Content -LiteralPath $j
"ARMED="+(Get-Date -Format 'HH:mm:ss') | Add-Content -LiteralPath $j
"VERDICT: ARMED_LONG_COVER_GO11_3" | Add-Content -LiteralPath $j
exit 0