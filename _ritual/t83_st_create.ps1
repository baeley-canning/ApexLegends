# t83_st_create.ps1 - click CREATE ACCOUNT on the EA sign-in page via CDP, then harvest the signup form.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t83_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== CREATE CLICK'

. (Join-Path $here '_cdp.ps1')
$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE TARGET'; exit 1 }
J ('ON ' + $pg.url)

# click the create-account control by text match
$clickJs = @'
(function(){
  var els = document.querySelectorAll('a, button, [role=button], wf-button');
  for (var i=0;i<els.length;i++){
    var t=(els[i].textContent||els[i].innerText||'').replace(/\s+/g,' ').trim();
    if (/create\s*(an\s*)?account/i.test(t)){
      var r=els[i].getBoundingClientRect();
      els[i].click();
      return 'CLICKED:['+t+'] rect='+Math.round(r.x)+','+Math.round(r.y);
    }
  }
  // fallback: any anchor whose href mentions create
  var as=document.querySelectorAll('a[href]');
  for (var k=0;k<as.length;k++){ if(/create/i.test(as[k].href)){ var h=as[k].href; as[k].click(); return 'CLICKED_HREF:'+h; } }
  return 'NOT_FOUND';
})()
'@
$f = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
    -Params @{ expression = $clickJs; returnByValue = $true } -Id 11
$res = '?'
if ($f -and $f.result -and $f.result.result) { $res = [string]$f.result.result.value }
J ('CLICK RESULT ' + $res)

# wait for navigation, report where we ended up
$newUrl = ''
foreach ($i in 1..12) {
    Start-Sleep -Seconds 2
    $locs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $pgs = @($locs | Where-Object { $_.type -eq 'page' })
    if ($pgs.Count -gt 0) { $newUrl = $pgs[0].url }
    J ("nav $i " + $newUrl)
    if ($newUrl -match 'create|signup') { break }
}

# harvest the new page
$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg2) { $pg2 = Get-CdpPage -Port 9333 -Index 1 }
if ($pg2) {
    $js = [IO.File]::ReadAllText((Join-Path $here 't80_domread.js'))
    $f2 = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
        -Params @{ expression = $js; returnByValue = $true } -Id 12
    if ($f2 -and $f2.result -and $f2.result.result) {
        ([string]$f2.result.result.value) | Out-File -Encoding utf8 (Join-Path $here '_dom2_create.txt')
        J 'DOM2 SAVED'
    }
    $s = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 82 } -Id 13
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t83_create.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SCREENSHOT SAVED'
    }
}
J '=== DONE'
