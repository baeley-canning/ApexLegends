# go14_standup - 20/11 full-stack bring-up after the h413..h419 adjudication.
# Sequel to bridge_seq/go11_watch2. Order: bridge consumer first (no dark screen,
# bridge_seq precedent), then an arm-on-apex watcher: the moment r5apex_dx12 is
# born it gives a 90 s lobby grace, then fires go11_arm_4 (arm_3 clone, fresh
# numbers) with the arm_3 guards (game alive, zero of OUR producers, QK_NO_PEB=1).
# Honest expectation: qk_va --emit rides the DTB discovery lane that h419 found
# severed on THIS boot, so arms may come home FAIL(no-dtb) - the watcher cools
# down 300 s between arms, caps at 3, then parks with a verdict instead of
# hammering. Stop-hook: temp\go14_stop.txt. Journal: temp\go14_standup.txt (R3),
# rolling single-line state: temp\go14_status.txt.
$repo='C:\Users\New User\OneDrive\Desktop\cheating'
$t   =Join-Path $repo 'temp'
$py  ="$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
$j   =Join-Path $t 'go14_standup.txt'
$st  =Join-Path $t 'go14_status.txt'
$stop=Join-Path $t 'go14_stop.txt'
$arm4=Join-Path $t 'go11_arm_4.ps1'
'WAKE '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Set-Content -LiteralPath $j
Remove-Item -LiteralPath $stop -Force -EA SilentlyContinue
# -- 1) bridge consumer: eats qk_feed.json whenever it births; 1500 s life -----
# REUSE-GUARD (learned 20/11: a watcher restart must not double-spawn overlays;
# one 1500-s qk_live is enough and a stale feed delete would blind a live one).
$reuse=@(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -EA SilentlyContinue |
         Where-Object { $_.CommandLine -match 'qk_live\.py.*--seconds=1500' })
if($reuse.Count -gt 0){
  ('BRIDGE_REUSE pid='+$reuse[0].ProcessId+' n='+$reuse.Count) | Add-Content -LiteralPath $j
}else{
  Remove-Item -LiteralPath (Join-Path $t 'qk_feed.json') -Force -EA SilentlyContinue
  $ba = '-u "{0}" --from-feed --seconds=1500' -f (Join-Path $repo 'ext\qk_live.py')
  $b=Start-Process -FilePath $py -WindowStyle Hidden -PassThru `
      -RedirectStandardOutput (Join-Path $t 'live_bridge_out2.txt') `
      -RedirectStandardError   (Join-Path $t 'live_bridge_err2.txt') `
      -ArgumentList $ba
  ('BRIDGE_PID='+$b.Id+' ARGS='+$ba) | Add-Content -LiteralPath $j
  Start-Sleep -Seconds 2
  ('BRIDGE_ALIVE2S='+(-not $b.HasExited)) | Add-Content -LiteralPath $j
}
# -- 2) arm-on-apex watcher ----------------------------------------------------
$graceSeen=$false; $race=0; $arms=0
for($i=0; $i -lt 720; $i++){
  try{
  if(Test-Path -LiteralPath $stop){ ('EVENT ['+(Get-Date -Format HH:mm:ss)+'] STOPFILE') | Add-Content -LiteralPath $j; break }
  $g=@(Get-Process r5apex_dx12 -EA SilentlyContinue)
  if($g.Count -gt 0){
    if(-not $graceSeen){ $graceSeen=$true; $race=0; ('EVENT ['+(Get-Date -Format HH:mm:ss)+'] GAME_SIGHTED pid='+$g[0].Id+' -> 90 s lobby grace') | Add-Content -LiteralPath $j }
    $race++
    if($race -eq 9){
      # guards inherited from go11_arm_3: producers-exclusive, fresh pid, hygiene
      $mine=@(Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'qk_va\.py' })
      if($mine.Count -gt 0){
        ('EVENT ['+(Get-Date -Format HH:mm:ss)+'] SKIP_ARM our producers still alive n='+$mine.Count) | Add-Content -LiteralPath $j
      } elseif(-not (Test-Path -LiteralPath $arm4)){
        ('EVENT ['+(Get-Date -Format HH:mm:ss)+'] SKIP_ARM missing '+$arm4) | Add-Content -LiteralPath $j
      } else {
        $arms++
        ('EVENT ['+(Get-Date -Format HH:mm:ss)+'] ARM #'+$arms+' -> go11_arm_4') | Add-Content -LiteralPath $j
        & $arm4 | Out-Null
        $vj=Get-Content (Join-Path $t 'go11_arm_4.txt') -EA SilentlyContinue | Select-Object -Last 1
        ('EVENT ['+(Get-Date -Format HH:mm:ss)+'] arm4 verdict: '+$vj) | Add-Content -LiteralPath $j
        if($vj -match 'ABORT_NO_R5|FAIL'){ Start-Sleep -Seconds 300 }   # cool-down, do not hammer a dead lane
      }
      $race=0
    }
  } else { $graceSeen=$false; $race=0 }
  $feed=Get-Item (Join-Path $t 'qk_feed.json') -EA SilentlyContinue
  ('{0} i={1} game={2} arms={3} feedAge={4}' -f (Get-Date -Format HH:mm:ss),$i,@($g).Count,$arms,($(if($feed){[math]::Round(((Get-Date)-$feed.LastWriteTime).TotalSeconds,1)}else{-1}))) | Set-Content -LiteralPath $st
  }catch{ ('EXC ['+(Get-Date -Format HH:mm:ss)+'] '+$_.Exception.Message) | Add-Content -LiteralPath $j }
  Start-Sleep -Seconds 10
}
('END '+[DateTime]::Now.ToString('HH:mm:ss')+' ARMS='+$arms) | Add-Content -LiteralPath $j
'VERDICT: GO14_STANDUP_WATCHER_DONE' | Add-Content -LiteralPath $j
exit 0