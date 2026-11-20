# t115_st_claim.ps1 - claim clean EA ID (no 'ea' prefix) on Complete-your-Account page; ride to session.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t115_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
'RUNNING' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J '=== CLAIM'

. (Join-Path $here '_cdp.ps1')

$NEWID = 'zk499064xz'
$PW = '6&Fjd5H@4hbzy5x7'

# universal find-tab (login exec or wherever finalization lives)
$tabs = Get-HttpJson 'http://127.0.0.1:9333/json/list'
$t2 = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if (-not $t2) { J 'NO TAB'; 'NO-TAB' | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt'); exit 1 }
$ws2 = $t2.webSocketDebuggerUrl
J ('AT ' + $t2.url.Substring(0, [Math]::Min(80, $t2.url.Length)))

# ritual fill clean ID + press #updateBtn
$go = @'
(function(){
  var ID='__ID__', PW='__PW__';
  var proto=window.HTMLInputElement.prototype;
  var dsc=Object.getOwnPropertyDescriptor(proto,'value');
  function ev(el,t){el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true}));}
  function typeInto(el,text){dsc.set.call(el,'');ev(el,'input');el.focus();
    for(var i=0;i<text.length;i++){var ch=text.charAt(i);
      el.dispatchEvent(new KeyboardEvent('keydown',{key:ch,bubbles:true,cancelable:true}));
      el.dispatchEvent(new KeyboardEvent('keypress',{key:ch,bubbles:true,cancelable:true}));
      dsc.set.call(el,el.value+ch);ev(el,'input');
      el.dispatchEvent(new KeyboardEvent('keyup',{key:ch,bubbles:true,cancelable:true}));}
    ev(el,'change');el.blur();}
  var oid=document.getElementById('originId');
  if(!oid) return 'NOORIGIN';
  typeInto(oid,ID);
  var pw=document.getElementById('password');
  if(pw&&!pw.value) typeInto(pw,PW);
  var ub=document.getElementById('updateBtn');
  if(ub){var lk=(ub.className||'').indexOf('disabled')>=0;ub.click();return 'CLAIM'+(lk?'-BLIND':'-LIVE');}
  var fm=oid.closest('form');
  if(fm&&fm.requestSubmit){try{fm.requestSubmit();return 'RS-CLAIM';}catch(e){}}
  return 'NOTHING';
})()
'@
$go = $go.Replace('__ID__', $NEWID).Replace('__PW__', $PW)
$f1 = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{ expression = $go; returnByValue = $true } -Id 740
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('CLAIM ' + $v1)

# ride: 10 legs, each with quick adaptive peek (privacy toggles may appear)
$outcome = 'CLAIM-UNCLEAR'
$pgNow = $t2
for ($i = 1; $i -le 10; $i++) {
    Start-Sleep -Seconds 3
    $tabs2 = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $tb = @($tabs2 | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
    $u = if ($tb) { $tb.url } else { '(gone)' }
    $sq = Invoke-CdpCmd -WsUrl $ws2 -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({s:(location.href.match(/s(\\d+)&/)||[])[1],ttl:document.title.slice(0,25),err:[].map.call(document.querySelectorAll('[class*=error],[role=alert]'),function(e){if(e.offsetParent)return (e.innerText||'').replace(/\s+/g,' ').trim().slice(0,60);}).filter(Boolean).slice(0,3),btns:[].map.call(document.querySelectorAll('button'),function(e){if(!(e.offsetWidth||e.offsetHeight))return null;return (e.innerText||'').replace(/\s+/g,' ').trim().slice(0,16);}).filter(Boolean).slice(0,5)})";
        returnByValue = $true } -Id (741 + $i)
    $sv = ''; if ($sq -and $sq.result -and $sq.result.result) { $sv = [string]$sq.result.result.value }
    J ("leg$i " + $sv + ' @' + $u.Substring(0, [Math]::Min(50, $u.Length)))
    if ($sv -match 'taken|prohibited|invalid') { $outcome = 'ID-REJECTED:' + $sv.slice(0, 40); break }
    if ($u -notmatch 'signin\.ea\.com' -and $u -notmatch 'juno/login') { $outcome = 'FINALIZED-SESSION-LIVE'; break }
}
$pgNow = (Get-HttpJson 'http://127.0.0.1:9333/json/list' | Where-Object { $_.type -eq 'page' -and $_.url -notmatch 'juno/create' }) | Select-Object -First 1
if ($pgNow) {
    $s = Invoke-CdpCmd -WsUrl $pgNow.webSocketDebuggerUrl -Method 'Page.captureScreenshot' -Params @{ format = 'jpeg'; quality = 80 } -Id 755
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t115_shot.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
}
$outcome | Out-File -Encoding ascii (Join-Path $here '_oracle_result.txt')
J ("FINAL $outcome")
J '=== DONE'
