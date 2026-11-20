# go11_planb - arm the feed pair on the POST-RESTART Apex instance (Plan B).
# Model: go11_arm_1.ps1. Differences: --peb-first producer lane (safe, ~1/3 RAM,
# never crashed the box tonight), fresh journals/outputs (R5: new numbers only),
# pid picked live at arm time (a restart means a NEW pid - the 25548 seed/wedge
# history is irrelevant to it). Called ONLY after the user confirms the game is
# back at the lobby. No wait loop; finishes in ~1 s.
# Journal: temp\go11_planb.txt  (R3: file is the verdict channel)
$repo='C:\Users\New User\OneDrive\Desktop\cheating'
$py="$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
$j=Join-Path $repo 'temp\go11_planb.txt'
"WAKE "+(Get-Date -Format 'HH:mm:ss') | Set-Content -LiteralPath $j
$g=@(Get-Process r5apex_dx12 -EA SilentlyContinue)
"RCOUNT=$($g.Count)" | Add-Content -LiteralPath $j
if($g.Count -eq 0){ "VERDICT: ABORT_NO_R5 (game not running yet?)" | Add-Content -LiteralPath $j; exit 2 }
"RPID=$($g[0].Id)" | Add-Content -LiteralPath $j
# pre-arm feed hygiene: stale feed out, fresh only
Remove-Item -LiteralPath (Join-Path $repo 'temp\qk_feed.json') -Force -EA SilentlyContinue
# producer: --peb-first puts the PEB-arbitrated scan ahead of the doomed
# shape-scan lane; discovery in menus is the cheapest window
$p1=Start-Process -FilePath $py -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $repo 'temp\emit_out4.txt') `
    -RedirectStandardError   (Join-Path $repo 'temp\emit_err4.txt') `
    -ArgumentList @('-u',('"'+(Join-Path $repo 'ext\qk_va.py')+'"'),'--emit','--hz=10','--secs=300','--peb-first')
# consumer: 330s drain, same ratio as go11 classic
$p2=Start-Process -FilePath $py -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $repo 'temp\live_out4.txt') `
    -RedirectStandardError   (Join-Path $repo 'temp\live_err4.txt') `
    -ArgumentList @('-u',('"'+(Join-Path $repo 'ext\qk_live.py')+'"'),'--from-feed','--seconds=330')
"PGONE=$($p1.Id) PGINT=$($p2.Id)" | Add-Content -LiteralPath $j
Start-Sleep -Milliseconds 800
"AFTER1S PROD_ALIVE=$(-not $p1.HasExited) CONS_ALIVE=$(-not $p2.HasExited)" | Add-Content -LiteralPath $j
"ARMED="+(Get-Date -Format 'HH:mm:ss') | Add-Content -LiteralPath $j
"VERDICT: ARMED_PAIR_PLANB" | Add-Content -LiteralPath $j
exit 0
