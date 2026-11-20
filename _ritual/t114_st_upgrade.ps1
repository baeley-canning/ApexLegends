# t114_st_upgrade.ps1 - s3 originId: photo, fill, advance, classify response.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t114_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
'RUNNING' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J '=== UPGRADE'

. (Join-Path $here '_cdp.ps1')

$tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
$t2 = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -match 'juno/login' }) | Select-Object -First 1
if (-not $t2) { J 'NO TAB'; 'NO-TAB' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt'); exit 1 }
$ws2 = $t2.webSocketDebuggerUrl

# 0. visual + textual census FIRST
$txt = @'
(function(){
  var h=[].map.call(document.querySelectorAll('h1,h2,h3,p,label'),function(e){
    if(!(e.offsetWidth||e.offsetHeight))return null;
    var t=(e.innerText||'').replace(/\s+/g,' ').trim();return t?t.slice(0,80):null;}).filter(Boolean).slice(0,15);
  var bs=[].map.call(document.querySelectorAll('button,a,[role=button]'),function(e){
    if(!(e.offsetWidth||e.offsetHeight))return null;
    return (e.innerText||'').replace(/\s+/g,' ').trim().slice(0,22)+'#'+(e.id||'-')+'|'+((e.className||'')+'').slice(0,25);}).filter(Boolean).slice(0,10);
  return JSON.stringify({steps:(location.href.match(/s(\d+)&/)||[])[1],txt:h,btns:bs});
})()
'@
$f0 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $txt; returnByValue = $true } -Id 710
$v0 = '?'; if ($f0 -and $f0.result -and $f0.result.result) { $v0 = [string]$f0.result.result.value }
J ('PGTXT ' + $v0)
$s0 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 711
if ($s0 -and $s0.result -and $s0.result.data) {
    [IO.File]::WriteAllBytes((Join-Path $here '_t114_a.jpg'), [Convert]::FromBase64String($s0.result.data))
    J 'SHOT-A'
}

# 1. fill originId + hunt any advance control
$go = @'
(function(){
  function fs(el,v){var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    st.call(el,v);['keydown','keypress','input','keyup','change'].forEach(function(t){
    el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true}));});el.blur();}
  var oid=document.getElementById('originId');
  if(!oid) return 'NOORIGIN';
  fs(oid,'ea499064xzacs');
  var btn=null,used='';
  var bs=document.querySelectorAll('button,[role=button],a[class*=btn],input[type=submit]');
  for(var i=0;i<bs.length;i++){var t=(bs[i].innerText||bs[i].value||'').replace(/\s+/g,' ').trim();
    if(/^(next|continue|submit|sign ?in|log ?in|create|update|save)$/i.test(t)&&(bs[i].offsetWidth||bs[i].offsetHeight)){
      if((bs[i].className||'').indexOf('disabled')>=0){used+='lock:'+t+';';continue;}
      btn=bs[i];used=t;break;}}
  if(btn){btn.click();return 'PRESSED:'+used;}
  var fm=oid.closest('form');
  if(fm&&fm.requestSubmit){try{fm.requestSubmit();return 'RS-U'+used;}catch(e){return 'RSERR';}}
  return 'NOTHING'+used;
})()
'@
$f1 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $go; returnByValue = $true } -Id 712
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('UPG ' + $v1)

# 2. classification ride
$verdict = 'UPGRADE-UNCLEAR'
for ($i = 1; $i -le 8; $i++) {
    Start-Sleep -Seconds 3
    $tabs2 = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $tb = @($tabs2 | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
    $u = if ($tb) { $tb.url } else { '(gone)' }
    $sq = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({s:(location.href.match(/s(\\d+)&/)||[])[1],err:[].map.call(document.querySelectorAll('[class*=error],[role=alert]'),function(e){if(e.offsetParent)return (e.innerText||'').replace(/\s+/g,' ').trim().slice(0,80);}).filter(Boolean).slice(0,3)})";
        returnByValue = $true } -Id (715 + $i)
    $sv = ''; if ($sq -and $sq.result -and $sq.result.result) { $sv = [string]$sq.result.result.value }
    J ("r$i " + $sv + ' @' + $u.Substring(0, [Math]::Min(55, $u.Length)))
    if ($sv -match 'taken') { $verdict = 'EAID-TAKEN-CONFIRMS-EXISTENCE'; break }
    if ($sv -match 'found|exist|invalid') { $verdict = 'ERROR:' + $sv.slice(0, 45); break }
    if ($u -notmatch 'juno/login' -and $u -notmatch 'signin\.ea\.com') { $verdict = 'SESSION-ESTABLISHED'; break }
    if (($u -match 's([3-9]|1\d)&' -and $sv -match '"s":"(4|[5-9]|1[0-9])"')) { $verdict = 'UPGRADE-ADVANCED'; }
}

# ANCHOR_ENDGAME
$verdict | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J ("FINAL $verdict")
$tlast = (Get-HttpJson 'http://127.0.0.1:9333/json/list' | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if ($tlast) {
    $s = Invoke-CdpCmd -WsUrl $tlast.webSocketDebuggerUrl -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 730
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t114_b.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT-B'
    }
}
# on strong verdicts, archive
if ($verdict -match 'SESSION-ESTABLISHED|ADVANCED|TAKEN-CONFIRMS') {
    $acct = [ordered]@{ eaId = 'ea499064xzacs'; email = 'ea499064xz@euploading.com'; password = '6&Fjd5H@4hbzy5x7'; createdAt = (Get-Date).ToString('s'); status = $verdict }
    ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
    J 'ARCHIVED-PARTIAL'
}
J '=== DONE'

