# t89_st_finish.ps1 - fill EA ID + password, tick agreement, CREATE ACCOUNT, archive credentials.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t89_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== FINISH'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
. (Join-Path $here '_cdp.ps1')

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
J ('ON ' + $pg.url)

$localPart = ($mail.address -split '@')[0]
$js = @'
(function(){
  var eaId = '__EAID__', pass = '__PASS__';
  function fs(el,v){ var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    st.call(el,v); ['keydown','keypress','input','keyup','change'].forEach(function(t){
      el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true})); }); }
  var vis=[]; var ins=document.querySelectorAll('input:not([type=hidden])');
  for (var i=0;i<ins.length;i++){ if(ins[i].offsetWidth||ins[i].offsetHeight) vis.push(ins[i]); }
  var got=[], pwBox=null, idBox=null;
  for (var k=0;k<vis.length;k++){
    var e=vis[k]; var sig=((e.id||'')+' '+(e.name||'')+' '+(e.type||'')).toLowerCase();
    if (e.type==='checkbox'){
      if(!e.checked){ e.click(); if(!e.checked){ e.checked=true; fs(e,e.value);} }
      got.push('chk@'+(e.id||'?')); continue;
    }
    if (/pass/.test(sig)) { pwBox=e; continue; }
    if (/eaid|ea-id|originid|persona/.test(sig)) { idBox=e; continue; }
  }
  // positional fallback: remaining text inputs [0]=id [1 or password-type]=pw
  var texts=vis.filter(function(x){return x.type==='text'&&/verification|back-form/.test((x.id||''))===false;});
  if(!idBox&&texts.length>0) idBox=texts[0];
  if(!pwBox){ var ps=vis.filter(function(x){return x.type==='password';}); if(ps.length>0) pwBox=ps[0]; }
  var res=[];
  if(idBox){ fs(idBox,eaId); res.push('ID='+idBox.id); }
  if(pwBox){ fs(pwBox,pass); res.push('PW='+pwBox.id); }
  // click CREATE ACCOUNT
  var nx=null; var bs=document.querySelectorAll('button, [role=button], wf-button');
  for (var b=0;b<bs.length;b++){ var t=(bs[b].textContent||'').replace(/\s+/g,' ').trim();
    if(/^create\s*account$|^create$/i.test(t)&&!/Sign/.test(t)){ nx=bs[b]; break; } }
  var cr='NOBTN';
  if(nx){ cr=nx.disabled?'DISABLED':'CLICKED'; if(!nx.disabled) nx.click(); }
  return res.join(' ')+' CHKS('+got.join(',')+') CREATE('+cr+')';
})()
'@
$js = $js.Replace('__EAID__', $localPart).Replace('__PASS__', $mail.password)
$f = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
    -Params @{ expression = $js; returnByValue = $true } -Id 81
$rv = '?'; if ($f -and $f.result -and $f.result.result) { $rv = [string]$f.result.result.value }
J ('FINISH ' + $rv)

# nav watch: success looks like leaving juno/create (redirect to ea.com / welcome / finish)
$finalUrl = ''
for ($i = 1; $i -le 10; $i++) {
    Start-Sleep -Seconds 3
    $loc = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $p0 = @($loc | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
    if ($p0) { $finalUrl = $p0.url; J ("nav $i " + $finalUrl) }
    if ($finalUrl -notmatch '/p/juno/create') { break }
}

# state + errors if still stuck
if ($finalUrl -match '/p/juno/create') {
    $st = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
        expression = "(function(){var es=[].map.call(document.querySelectorAll('[class*=error],[role=alert]'),function(e){return e.innerText.trim();}).filter(Boolean);return JSON.stringify({errs:es,url:location.href.slice(0,90)});})()";
        returnByValue = $true } -Id 82
    if ($st -and $st.result -and $st.result.result) { J ('ERRS ' + [string]$st.result.result.value) }
}

# harvest final
$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg2) {
    $rd = [IO.File]::ReadAllText((Join-Path $here 't80_domread.js'))
    $fr = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
        -Params @{ expression = $rd; returnByValue = $true } -Id 83
    if ($fr -and $fr.result -and $fr.result.result) {
        ([string]$fr.result.result.value) | Out-File -Encoding utf8 (Join-Path $here '_dom8_done.txt')
        J 'DOM8 SAVED'
    }
    $s = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 84
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t90_done.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
}

# credential archive
if ($finalUrl -notmatch '/p/juno/create') {
    $acct = [ordered]@{
        eaId       = $localPart
        email      = $mail.address
        password   = $mail.password
        createdAt  = (Get-Date).ToString('s')
        sourceMail = 'mail.tm accountId ' + $mail.accountId
        finalUrl   = $finalUrl
    }
    ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
    J 'ACCOUNT ARCHIVED'
}
J '=== DONE'
