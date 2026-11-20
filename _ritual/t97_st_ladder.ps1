# t97_st_ladder.ps1 - retype proven identity, blur arcs, forcing ladder: A(click-live) B(reblur+click) C(requestSubmit) D(blind click).
$ErrorActionPreference = 'Continue'
$here = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual'
$j = Join-Path $here '_t97_journal.txt'
function J($m) { Add-Content -Path $j -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) }
J '=== LADDER'

$mail = Get-Content (Join-Path $here '_mail.json') -Raw | ConvertFrom-Json
. (Join-Path $here '_cdp.ps1')

$id = 'ea499064xzacs'
$pw = '6&Fjd5H@4hbzy5x7'

$pg = Get-CdpPage -Port 9333 -Match 'ea.com'
if (-not $pg) { J 'NO PAGE'; exit 1 }
$ws = $pg.webSocketDebuggerUrl

$ladder = @'
(function(){
  var eaId='__EAID__', pass='__PASS__';
  window.__netlog=[];
  var of=window.fetch;
  window.fetch=function(){var u=(arguments[0]&&(arguments[0].url||arguments[0]))+'';
    var rec={u:u.slice(0,120)};window.__netlog.push(rec);
    return of.apply(this,arguments).then(function(r){rec.s=r.status;return r;});};
  var proto=window.HTMLInputElement.prototype;
  var dsc=Object.getOwnPropertyDescriptor(proto,'value');
  function ev(el,t){el.dispatchEvent(new Event(t,{bubbles:true,cancelable:true}));}
  function typeInto(el,text){
    dsc.set.call(el,'');ev(el,'input');el.focus();
    for(var i=0;i<text.length;i++){var ch=text.charAt(i);
      el.dispatchEvent(new KeyboardEvent('keydown',{key:ch,bubbles:true,cancelable:true}));
      el.dispatchEvent(new KeyboardEvent('keypress',{key:ch,bubbles:true,cancelable:true}));
      dsc.set.call(el,el.value+ch);ev(el,'input');
      el.dispatchEvent(new KeyboardEvent('keyup',{key:ch,bubbles:true,cancelable:true}));}
    ev(el,'change');el.blur();}
  function findBtn(){var bs=document.querySelectorAll('button,a,[role=button],wf-button');
    for(var i=0;i<bs.length;i++){var t=(bs[i].textContent||'').replace(/\s+/g,' ').trim();
      if(/^create\s*account$|^create$/i.test(t)&&!/Sign/.test(t))return bs[i];}return null;}
  function cls(b){return (b.className||'');}
  function live(b){return cls(b).indexOf('disabled')<0;}
  var idEl=document.getElementById('originId');
  var pwEl=document.querySelector('input[type=password]');
  if(!idEl||!pwEl) return 'MISSING';
  typeInto(idEl,eaId); typeInto(pwEl,pass);
  var chk=document.getElementById('readAccept');
  if(chk){chk.focus();if(!chk.checked)chk.click();chk.blur();}
  var btn=findBtn(); var out={};
  out.clsAfterType=btn?cls(btn).slice(0,60):'NOBTN';
  // PATH A
  if(btn&&live(btn)){btn.click();out.path='A';return JSON.stringify(out);}
  // PATH B: reblur arcs then re-check
  idEl.blur();pwEl.blur();if(chk){chk.focus();chk.blur();}
  ev(idEl,'change');ev(pwEl,'change');
  btn=findBtn();
  if(btn&&live(btn)){btn.click();out.path='B';return JSON.stringify(out);}
  // PATH C: native form submit
  var fm=document.querySelector('form');
  if(fm&&fm.requestSubmit){try{fm.requestSubmit();out.path='C';out.formAction=fm.action.slice(0,80);return JSON.stringify(out);}catch(e){out.cErr=(''+e).slice(0,60);}}
  // PATH D: blind click regardless of class
  if(btn){btn.click();out.path='D';return JSON.stringify(out);}
  out.path='NONE';return JSON.stringify(out);
})()
'@
$ladder = $ladder.Replace('__EAID__', $id).Replace('__PASS__', $pw)
$f1 = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{ expression = $ladder; returnByValue = $true } -Id 201
$v1 = '?'; if ($f1 -and $f1.result -and $f1.result.result) { $v1 = [string]$f1.result.result.value }
J ('LADDER ' + $v1)

# watch: nav + net samples (tight, ~18s)
for ($i = 1; $i -le 6; $i++) {
    Start-Sleep -Milliseconds 2600
    $loc = Get-HttpJson 'http://127.0.0.1:9333/json/list'
    $p0 = @($loc | Where-Object { $_.type -eq 'page' }) | Select-Object -First 1
    $u = if ($p0) { $p0.url } else { '?' }
    $short = if ($u.Length -gt 55) { $u.Substring(0, 55) } else { $u }
    $fn = Invoke-CdpCmd -WsUrl $ws -Method 'Runtime.evaluate' -Params @{
        expression = "JSON.stringify({n:(window.__netlog||[]).length,l:JSON.stringify((window.__netlog||[]).slice(0,3))})";
        returnByValue = $true } -Id (210 + $i)
    $vn = ''; if ($fn -and $fn.result -and $fn.result.result) { $vn = [string]$fn.result.result.value }
    J ("w$i $short NET $vn")
    if ($u -notmatch '/p/juno/create') { J 'OUT-OF-WIZARD'; break }
}

$pg2 = Get-CdpPage -Port 9333 -Match 'ea.com'
if ($pg2) {
    $s2 = Invoke-CdpCmd -WsUrl $pg2.webSocketDebuggerUrl -Method 'Page.captureScreenshot' `
        -Params @{ format = 'jpeg'; quality = 80 } -Id 220
    if ($s2 -and $s2.result -and $s2.result.data) {
        [IO.File]::WriteAllBytes((Join-Path $here '_t97_shot.jpg'), [Convert]::FromBase64String($s2.result.data))
        J 'SHOT SAVED'
    }
    if ($pg2.url -notmatch '/p/juno/create') {
        $acct = [ordered]@{ eaId = $id; email = $mail.address; password = $pw; createdAt = (Get-Date).ToString('s'); finalUrl = $pg2.url }
        ($acct | ConvertTo-Json) | Out-File -Encoding utf8 (Join-Path $here '_ea_account.json')
        J '=== ARCHIVED ok=True'
    } else { J '=== HELD AT S4 ok=False' }
}
