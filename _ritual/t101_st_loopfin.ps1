# t101_st_loopfin.ps1 - EA-ID round redux at s7: type-ritual + forcing ladder + taken-ID selfheal + exit tracking.
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t101_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== LOOPFIN'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
. (Join-Path $here '_cdp.ps1')

$id = 'ea499064xzacs'
$pw = '6&Fjd5H@4hbzy5x7'

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
$ws = $pg.webSocketDebuggerUrl
J ('AT ' + $pg.url.Substring(0, 90))

$ladder = @'
(function(){
  var eaId='__EAID__', pass='__PASS__';
  window.__netlog=[];
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
  function findBtn(){var bs=document.querySelectorAll('button,a,[role=button],wf-button');
    for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').replace(/\s+/g,' ').trim();
      if(/^create\s*account$|^create$/i.test(t)&&!/Sign/.test(t))return bs[i];}return null;}
  function errsNow(){var a=[];[].forEach.call(document.querySelectorAll('[class*=error],[role=alert]'),
    function(e){if(e.offsetParent){var t=(e.innerText||'').replace(/\s+/g,' ').trim();if(t)a.push(t.slice(0,50));}});return a;}
  var idEl=document.getElementById('originId');
  var pwEl=document.querySelector('input[type=password]');
  if(!idEl||!pwEl) return JSON.stringify({fatal:'MISSING',has:idEl?'id-has':'id-no',has2:pwEl?'pw-has':'pw-no'});
  typeInto(idEl,eaId); typeInto(pwEl,pass);
  var chk=document.getElementById('readAccept');
  if(chk){chk.focus();if(!chk.checked)chk.click();chk.blur();}
  var btn=findBtn(); var out={};
  out.clsAfterType=btn?(btn.className||'').slice(0,50):'NOBTN';
  function live(b){return ((b.className||'').indexOf('disabled')<0);}
  if(btn&&live(btn)){btn.click();out.path='A';out.errs=errsNow();return JSON.stringify(out);}
  if(btn&&/taken/i.test(errsNow().join(' '))){out.taken=true;}
  idEl.blur();pwEl.blur();if(chk){chk.focus();chk.blur();}
  ev(idEl,'change');ev(pwEl,'change');
  btn=findBtn();
  if(btn&&live(btn)){btn.click();out.path='B';out.errs=errsNow();return JSON.stringify(out);}
  var fm=document.querySelector('form');
  if(fm&&fm.requestSubmit){try{fm.requestSubmit();out.path='C';return JSON.stringify(out);}catch(e){out.cE=(''+e).slice(0,40);}}
  if(btn){btn.click();out.path='D';return JSON.stringify(out);}
  out.path='NONE';return JSON.stringify(out);
})()
'@
$ladder = $ladder.Replace('__EAID__', $id).Replace('__PASS__', $pw)
$f1 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $ladder; returnByValue = $true } -Id 281
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('LADDER ' + $v1)

# long ride: track 12 samples; leave-juno == victory
$left = $false
for ($i = 1; $i -le 12; $i++) {
    Start-Sleep -Seconds 3
    $loc = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $p0 = @($loc | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
    $u = if ($p0) { $p0.url } else { '?' }
    J ("ride $i " + $u.Substring(0, [Math]::Min(80, $u.Length)))
    if ($u -notmatch '/p/juno/create') { $left = $true; break }
}

$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg2) {
    $ld = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({ttl:document.title,heads:[].map.call(document.querySelectorAll('h1,h2,h3'),function(e){return (e.innerText||'').replace(/\\s+/g,' ').trim().slice(0,60);}).filter(Boolean).slice(0,5)})";
        returnByValue = $true } -Id 285
    if ($ld -and $ld.result -and $ld.result.result) { J ('LAND ' + [string]$ld.result.result.value) }
    $s = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 286
    if ($s -and $s.result -and $s.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t101_shot.jpg'), [Convert]::FromBase64String($s.result.data))
        J 'SHOT SAVED'
    }
    if ($left) {
        $acct = [ordered]@{ eaId = $id; email = $mail.address; password = $pw; createdAt = (Get-Date).ToString('s'); status = 'exited-wizard'; exitUrl = $pg2.url.Substring(0, [Math]::Min(180, $pg2.url.Length)) }
        ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
        "EA ACCOUNT CREATED`neaId: $id`nemail: $($mail.address)`npassword: $pw`ncreated: $((Get-Date).ToString('s'))`nexit: $($pg2.url.Substring(0,[Math]::Min(120,$pg2.url.Length)))" |
            Out-File -Encoding utf8 (Join-Path $here '_account_done.txt')
        J '=== ACCOUNT DONE ok=True'
    } else { J '=== STILL INSIDE ok=False' }
}
