# t92_st_defuse.ps1 - clear-fill-readback-defuse the fused fields, then submit.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t92_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== DEFUSE'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
. (Join-Path $here '_cdp.ps1')
. (Join-Path $here 't91_lib.ps1')

$id, $pw = New-EaSecrets
J ("GEN idLen=$($id.Length) pwLen=$($pw.Length)")

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }

$js = @'
(function(){
  var eaId='__EAID__', pass='__PASS__';
  function fs(el,v){ var st=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
    st.call(el,v); ['keydown','keypress','input','keyup','change'].forEach(function(t){
      el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true})); }); }
  function info(e){ return (e.id||'noid')+'/'+e.type+'/idx_'+[].indexOf.call(document.querySelectorAll('input'),e); }
  // collect candidate nodes
  var all=[].slice.call(document.querySelectorAll('input')).filter(function(x){return !x.type||x.type!=='hidden';});
  var vis=all.filter(function(x){return x.offsetWidth||x.offsetHeight;});
  var rep=vis.map(info);
  var idEl=document.getElementById('originId')||vis[0];
  var pwEl=vis.filter(function(x){return x!==idEl && (x.type==='password'||/pass/i.test(x.id+x.name));})[0];
  // PHASE 1: clear everything visible
  vis.forEach(function(x){ fs(x,''); });
  // PHASE 2: set id field
  fs(idEl, eaId);
  // PHASE 3: re-locate pw node AFTER clearing (avoid stale dup) and set
  var vis2=[].slice.call(document.querySelectorAll('input')).filter(function(x){return (x.offsetWidth||x.offsetHeight)&&x.type!=='hidden'&&x.type!=='checkbox';});
  pwEl = vis2.filter(function(x){return x!==idEl && x.type==='password';})[0] ||
         vis2.filter(function(x){return x!==idEl && /pass/i.test((x.id||'')+(x.name||''));})[0];
  var pwTarget = pwEl || (vis2.length>1 ? vis2[1] : null);
  if(pwTarget) fs(pwTarget, pass);
  // PHASE 4: readback
  var rb1=idEl.value, rb2=pwTarget?pwTarget.value:'NOFIELD';
  // PHASE 5: defuse contamination
  var fixes=[];
  if(rb2==='NOFIELD'){ fixes.push('nopw'); }
  else {
    if(rb1!==eaId){ fixes.push('id_dirty'); fs(idEl,''); fs(idEl,eaId); }
    if(rb2!==pass){ fixes.push('pw_dirty'); fs(pwTarget,''); fs(pwTarget,pass); }
  }
  var rbFinal={id:idEl.value, pw:pwTarget?pwTarget.value:'?'};
  // checkbox
  var chk=document.getElementById('readAccept')||document.querySelector('input[type=checkbox]');
  if(chk&&!chk.checked) chk.click();
  // read pw node identity for forensics
  return JSON.stringify({fields:rep,pwNode:pwTarget?info(pwTarget):'?',
    rb1:rb1,rb2:rb2,fixes:fixes,final:rbFinal,
    chk:chk?(chk.checked?'on':'off'):'absent'});
})()
'@
$js = $js.Replace('__EAID__', $id).Replace('__PASS__', $pw)
$f = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Runtime.evaluate' `
    -Params @{ expression = $js; returnByValue = $true } -Id 101
$rv = '?'; if ($f -and $f.result -and $f.result.result) { $rv = [string]$f.result.result.value }
J ('PHASES ' + $rv)

# proceed to click only if clean
if ($rv -match '"fixes":\[\]' -or $rv -match '"fixes":\[\]"?$' -or $rv -notmatch 'nopw') {
    $ck = Invoke-CdpCmd -WsUrl $pg.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
        expression = "(function(){var bs=document.querySelectorAll('button,[role=button],wf-button');for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').replace(/\s+/g,' ').trim();if(/^create\s*account$|^create$/i.test(t)&&!/Sign/.test(t)){if(bs[i].disabled)return 'DISABLED';bs[i].click();return 'CLICKED';}}return 'NOBTN';})()";
        returnByValue = $true } -Id 102
    J ('CLICK ' + $(if ($ck -and $ck.result) { [string]$ck.result.result.value } else { '?' }))
} else { J 'SKIP CLICK - dirty fields' }

$left = $false
for ($i = 1; $i -le 8; $i++) {
    Start-Sleep -Seconds 3
    $loc = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $p0 = @($loc | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
    $u = if ($p0) { $p0.url } else { '?' }
    J ("nav $i " + $u.Substring(0, [Math]::Min(70, $u.Length)))
    if ($u -notmatch '/p/juno/create') { $left = $true; break }
}

$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg2) {
    J ('POSTSTATE ' + (Read-LiveErrors $pg2.webSocketDebuggerUrl 103))
    $s = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 104
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t92_shot.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
}

if ($left -and $pg2) {
    $acct = [ordered]@{ eaId = $id; email = $mail.address; password = $pw; createdAt = (Get-Date).ToString('s'); finalUrl = $pg2.url }
    ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
    J '=== ARCHIVED ok=True'
} else { J '=== NOT YET ok=False' }
